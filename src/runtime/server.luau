--!strict
-- Orchestration only: every effect arrives as a dependency, so this module holds no Roblox
-- globals and can be started against fakes in Lune. The Roblox implementations of those
-- dependencies live in runtime/net.luau and runtime/host.luau.

local Types = require("../logic/types")
local Result = require("../logic/result")
local Economy = require("../logic/economy")
local Progression = require("../logic/progression")
local Profile = require("../logic/profile")
local Events = require("../logic/events")

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type StateSnapshot = Types.StateSnapshot
type Action = Types.Action
type Result<T> = Result.Result<T>

export type Presence = {
	onJoin: (self: Presence, handler: (userId: number) -> ()) -> (),
	onLeave: (self: Presence, handler: (userId: number) -> ()) -> (),
	onClose: (self: Presence, handler: () -> ()) -> (),
	kick: (self: Presence, userId: number, message: string) -> (),
	playerOf: (self: Presence, userId: number) -> any?,
}

export type Transport = {
	sendState: (self: Transport, userId: number, snapshot: StateSnapshot) -> (),
	onAction: (self: Transport, handler: (userId: number, action: Action) -> Result<StateSnapshot>) -> (),
}

export type Scheduler = {
	every: (self: Scheduler, seconds: number, handler: () -> ()) -> (),
}

export type Deps = {
	config: TitleConfig,
	data: any,
	market: any,
	analytics: any,
	presence: Presence,
	transport: Transport,
	scheduler: Scheduler,
	clock: () -> number,
	snapshotHeartbeat: number,
}

export type GameServer = {
	start: (self: GameServer) -> (),
	profileOf: (self: GameServer, userId: number) -> ProfileData?,
}

local Runtime = {}
Runtime.__index = Runtime

local KICK_MESSAGES = {
	ProfileLocked = "Your save is in use on another server. Rejoin in a moment.",
	SchemaTooNew = "Your save was written by a newer version of the game.",
	ProfileCorrupt = "Your save could not be read. Nothing was overwritten.",
}

function Runtime.server(deps: Deps): GameServer
	local self = setmetatable({
		_deps = deps,
		_profiles = {},
	}, Runtime)
	return (self :: any) :: GameServer
end

function Runtime:profileOf(userId: number): ProfileData?
	return self._profiles[userId]
end

function Runtime:_snapshot(userId: number): StateSnapshot?
	local profile = self._profiles[userId]
	if profile == nil then
		return nil
	end
	local deps: Deps = self._deps
	return {
		wallet = profile.wallet,
		upgrades = profile.upgrades,
		rebirths = profile.rebirths,
		incomePerSecond = Economy.incomePerSecond(profile, deps.config, deps.market:ownedPassIds(userId)),
	}
end

function Runtime:_balances(profile: ProfileData): string
	local parts = {}
	for _, currency in self._deps.config.currencies do
		table.insert(parts, `{currency.id}={profile.wallet[currency.id] or 0}`)
	end
	for upgradeId, level in profile.upgrades do
		table.insert(parts, `{upgradeId}={level}`)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

function Runtime:_commit(userId: number, profile: ProfileData)
	self._profiles[userId] = profile
	self._deps.data:sync(userId, profile)
end

function Runtime:_push(userId: number)
	local snapshot = self:_snapshot(userId)
	if snapshot then
		self._deps.transport:sendState(userId, snapshot)
	end
end

function Runtime:_join(userId: number)
	local deps: Deps = self._deps
	local loaded = deps.data:load(userId)
	if not loaded.ok then
		deps.presence:kick(userId, KICK_MESSAGES[loaded.code] or loaded.message)
		return
	end

	local profile = Profile.touch(loaded.value, deps.clock())
	self._profiles[userId] = profile
	-- Printed on purpose: AC-6 is verified by comparing this number with the HUD and with
	-- the matching save line, and Studio's Output is the only place both are visible.
	print(`[{deps.config.slug}] loaded {userId}: {self:_balances(profile)}`)
	self:_push(userId)
end

function Runtime:_leave(userId: number)
	local deps: Deps = self._deps
	local profile = self._profiles[userId]
	if profile then
		-- Forced save on the way out; the periodic one belongs to the data adapter.
		local saved = Profile.touch(profile, deps.clock())
		print(`[{deps.config.slug}] saving {userId}: {self:_balances(saved)}`)
		deps.data:save(userId, saved)
	end
	self._profiles[userId] = nil
	deps.market:forget(userId)
	deps.data:release(userId)
end

function Runtime:_act(userId: number, action: Action): Result<StateSnapshot>
	local deps: Deps = self._deps
	local profile = self._profiles[userId]
	if profile == nil then
		return Result.err("ProfileNotLoaded", "profile is still loading")
	end
	if type(action) ~= "table" then
		return Result.err("UnknownUpgrade", "malformed action")
	end

	local player = deps.presence:playerOf(userId)

	if action.kind == "BuyUpgrade" then
		local bought = Progression.buyUpgrade(profile, deps.config, tostring(action.upgradeId))
		if not bought.ok then
			return bought
		end
		self:_commit(userId, bought.value)

		local level = bought.value.upgrades[action.upgradeId]
		local def = Economy.findUpgrade(deps.config, action.upgradeId)
		if player and def then
			local spent = Economy.upgradeCost(def, level - 1)
			deps.analytics:economy(player, Events.economy(bought.value, def.currency, -spent, "Shop"))
			deps.analytics:progression(player, Events.progression(bought.value, action.upgradeId, level))
		end
	elseif action.kind == "Rebirth" then
		local reborn = Progression.rebirth(profile, deps.config)
		if not reborn.ok then
			return reborn
		end
		self:_commit(userId, reborn.value)
	elseif action.kind == "PromptPass" then
		if player then
			deps.market:promptPass(player, action.passId)
		end
	else
		return Result.err("UnknownUpgrade", tostring((action :: any).kind))
	end

	local snapshot = self:_snapshot(userId)
	if snapshot == nil then
		return Result.err("ProfileNotLoaded", "profile went away mid-action")
	end
	self:_push(userId)
	return Result.ok(snapshot)
end

-- Runs inside ProcessReceipt: true only once the grant is on disk, because Roblox stops
-- resending a receipt the moment it is acknowledged.
function Runtime:_receipt(userId: number, productId: string, receiptId: string): boolean
	local deps: Deps = self._deps
	local profile = self._profiles[userId]
	if profile == nil then
		return false
	end

	local def = nil
	for _, candidate in deps.config.products do
		if candidate.id == productId then
			def = candidate
			break
		end
	end
	if def == nil then
		return false
	end

	local granted = Profile.applyProductGrant(profile, def, receiptId, deps.clock())
	if not granted.ok then
		-- An already-processed receipt is a success from Roblox's side: the player has the
		-- goods, and repeating the grant is exactly what must not happen.
		return granted.code == "ReceiptAlreadyProcessed"
	end

	local saved = deps.data:save(userId, granted.value)
	if not saved.ok then
		return false
	end

	self._profiles[userId] = granted.value
	self:_push(userId)
	return true
end

function Runtime:start()
	local deps: Deps = self._deps

	deps.presence:onJoin(function(userId)
		self:_join(userId)
	end)
	deps.presence:onLeave(function(userId)
		self:_leave(userId)
	end)
	deps.presence:onClose(function()
		for userId in self._profiles do
			self:_leave(userId)
		end
	end)

	deps.transport:onAction(function(userId, action)
		return self:_act(userId, action)
	end)

	deps.market:onReceipt(function(userId, productId, receiptId)
		return self:_receipt(userId, productId, receiptId)
	end)

	deps.scheduler:every(1, function()
		for userId, profile in self._profiles do
			local income = Economy.incomePerSecond(profile, deps.config, deps.market:ownedPassIds(userId))
			local earned = Economy.earn(profile, deps.config.currencies[1].id, income)
			if earned.ok then
				self:_commit(userId, earned.value)
			end
		end
	end)

	-- Passive income changes the balance without any action to answer, so the client needs
	-- a periodic snapshot; per-frame pushes would be the same numbers sixty times a second.
	deps.scheduler:every(deps.snapshotHeartbeat, function()
		for userId in self._profiles do
			self:_push(userId)
		end
	end)
end

return Runtime

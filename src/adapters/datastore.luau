--!strict
-- ProfileStore wrapper. The session lock itself is ProfileStore's job (S-03: the racy
-- network half is exactly what hand-rolled locks get wrong); this module only maps its
-- API onto the Result contract and owns the retry policy for forced saves.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local Packages = script.Parent.Parent
local Types = require(Packages.logic.types)
local Result = require(Packages.logic.result)
local Profile = require(Packages.logic.profile)

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type Result<T> = Result.Result<T>

local RECEIPT_MAX_AGE = 90 * 24 * 60 * 60 -- Roblox never resends a receipt this old (S-03)

export type DataAdapter = {
	load: (self: DataAdapter, userId: number) -> Result<ProfileData>,
	save: (self: DataAdapter, userId: number, profile: ProfileData) -> Result<true>,
	release: (self: DataAdapter, userId: number) -> (),
}

export type Options = {
	storeName: string,
	config: TitleConfig,
	autosaveSeconds: number,
	maxAttempts: number,
	staleAfterSeconds: number,
	-- Called from ProfileStore's Cancel handler: the adapter must not know about Players.
	isActive: (userId: number) -> boolean,
	-- Fired when ProfileStore drops the session under us (another server stole the lock).
	-- The player has to be kicked, or they keep playing a profile nobody is saving.
	onSessionEnd: ((userId: number) -> ())?,
}

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

function DataStoreAdapter.new(opts: Options): DataAdapter
	-- Both are ProfileStore-wide, not per-store. Autosave defaults to 300 s, so leaving it
	-- alone means up to five minutes of lost progress on a crash, where BindToClose never
	-- runs (S-03). SESSION_STEAL defaults to 40 s.
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", opts.autosaveSeconds)
	ProfileStore.SetConstant("SESSION_STEAL", opts.staleAfterSeconds)

	-- A Studio play-test must never touch the live store.
	local storeName = if RunService:IsStudio() then opts.storeName .. "_studio" else opts.storeName

	local self = setmetatable({
		_opts = opts,
		_store = ProfileStore.New(storeName, Profile.new(opts.config, os.time())),
		_sessions = {},
	}, DataStoreAdapter)

	return (self :: any) :: DataAdapter
end

function DataStoreAdapter:load(userId: number): Result<ProfileData>
	local opts: Options = self._opts

	local session = self._store:StartSessionAsync(`Player_{userId}`, {
		Cancel = function()
			return not opts.isActive(userId)
		end,
	})

	if session == nil then
		return Result.err("ProfileLocked", `session for {userId} is held elsewhere`)
	end

	local migrated = Profile.migrate(session.Data)
	if not migrated.ok then
		-- Unreadable or newer-than-us data: end the session without writing, so the bad
		-- value survives for inspection instead of being overwritten by a fresh profile.
		session:EndSession()
		return migrated
	end

	session:AddUserId(userId)
	session:Reconcile()

	-- Mutated in place: ProfileStore saves the table it handed out, so reassigning
	-- session.Data would leave it saving the old one.
	local pruned = Profile.pruneReceipts(migrated.value, os.time(), RECEIPT_MAX_AGE)
	session.Data.processedReceipts = pruned.processedReceipts

	session.OnSessionEnd:Connect(function()
		self._sessions[userId] = nil
		if opts.onSessionEnd then
			opts.onSessionEnd(userId)
		end
	end)

	if not opts.isActive(userId) then
		session:EndSession()
		return Result.err("ProfileLocked", `{userId} left while the session was loading`)
	end

	self._sessions[userId] = session
	return Result.ok(session.Data)
end

function DataStoreAdapter:save(userId: number, profile: ProfileData): Result<true>
	local session = self._sessions[userId]
	if session == nil then
		return Result.err("ProfileNotLoaded", `no session for {userId}`)
	end

	-- Field-by-field for the same reason as above: the saved table must stay the same table.
	session.Data.wallet = profile.wallet
	session.Data.upgrades = profile.upgrades
	session.Data.rebirths = profile.rebirths
	session.Data.processedReceipts = profile.processedReceipts
	session.Data.stats = profile.stats

	local delay = 1
	for attempt = 1, self._opts.maxAttempts do
		local ok, err = pcall(function()
			session:Save()
		end)
		if ok then
			return Result.ok(true)
		end
		if attempt == self._opts.maxAttempts then
			return Result.err("DataStoreUnavailable", `save for {userId} failed {attempt}x: {err}`)
		end
		task.wait(delay)
		delay *= 2
	end

	return Result.err("DataStoreUnavailable", `save for {userId} exhausted attempts`)
end

function DataStoreAdapter:release(userId: number)
	local session = self._sessions[userId]
	if session then
		self._sessions[userId] = nil
		session:EndSession()
	end
end

return DataStoreAdapter

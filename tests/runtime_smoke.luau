--!strict
-- Boots the real Runtime against fake adapters: everything the server does between a join
-- and a purchase is orchestration, and orchestration is the part Lune can still check.

local Runtime = require("../src/runtime/server")
local Profile = require("../src/logic/profile")
local Config = require("../src/logic/config")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local NOW = 1_756_000_000
local USER = 777

local function fakes(config)
	local stored = Profile.new(config, NOW)
	local state = {
		saved = 0,
		synced = 0,
		released = false,
		kicked = nil :: string?,
		snapshots = {},
		ticks = {},
		join = nil :: ((number) -> ())?,
		leave = nil :: ((number) -> ())?,
		act = nil :: any,
		receipt = nil :: any,
		loadResult = nil :: any,
		syncFails = false,
		saveFails = false,
	}

	local data = {
		load = function(_, _userId)
			return state.loadResult or { ok = true, value = stored }
		end,
		sync = function(_, _userId, profile)
			state.synced += 1
			if state.syncFails then
				return { ok = false, code = "ProfileNotLoaded", message = "session gone" }
			end
			stored = profile
			return { ok = true, value = true }
		end,
		save = function(_, _userId, profile)
			state.saved += 1
			if state.saveFails then
				return { ok = false, code = "DataStoreUnavailable", message = "not confirmed" }
			end
			stored = profile
			return { ok = true, value = true }
		end,
		release = function()
			state.released = true
		end,
	}

	local market = {
		ownedPassIds = function()
			return {}
		end,
		promptPass = function() end,
		promptProduct = function() end,
		forget = function() end,
		onReceipt = function(_, handler)
			state.receipt = handler
		end,
	}

	local analytics = {
		economy = function() end,
		progression = function() end,
	}

	local presence = {
		onJoin = function(_, handler)
			state.join = handler
		end,
		onLeave = function(_, handler)
			state.leave = handler
		end,
		onClose = function() end,
		kick = function(_, _userId, message)
			state.kicked = message
		end,
		playerOf = function()
			return nil
		end,
	}

	local transport = {
		sendState = function(_, _userId, snapshot)
			table.insert(state.snapshots, snapshot)
		end,
		onAction = function(_, handler)
			state.act = handler
		end,
	}

	local scheduler = {
		every = function(_, seconds, handler)
			table.insert(state.ticks, { seconds = seconds, handler = handler })
		end,
	}

	return state,
		{
			config = config,
			data = data,
			market = market,
			analytics = analytics,
			presence = presence,
			transport = transport,
			scheduler = scheduler,
			clock = function()
				return NOW
			end,
			snapshotHeartbeat = 5,
		}
end

return function(t)
	local validated = Config.validate(serde.decode("json", fs.readFile("tests/fixtures/main.json")))
	assert(validated.ok, "fixture must validate")
	local config = validated.value

	local state, deps = fakes(config)
	local server = Runtime.server(deps)
	server:start()

	t:check("start subscribes to joins", state.join ~= nil)
	t:check("start subscribes to actions", state.act ~= nil)
	t:eq("income and heartbeat are the only loops", #state.ticks, 2)

	t:eq("no profile before the join", server:profileOf(USER), nil)
	state.join(USER)
	t:check("profile is loaded on join", server:profileOf(USER) ~= nil)
	t:eq("join pushes a first snapshot", #state.snapshots, 1)

	-- Income tick, then a purchase paid for by it.
	local income = state.ticks[1].handler
	for _ = 1, 40 do
		income()
	end
	local afterIncome = server:profileOf(USER)
	t:check("income accrues on the tick", afterIncome.wallet.coins > 0)

	local bought = state.act(USER, { kind = "BuyUpgrade", upgradeId = "conveyor" })
	t:check("affordable upgrade succeeds", bought.ok)
	t:eq("level went up", server:profileOf(USER).upgrades.conveyor, 1)
	t:check("purchase syncs to storage", state.synced > 0)

	local poor = state.act(USER, { kind = "BuyUpgrade", upgradeId = "conveyor" })
	t:errs("second upgrade is unaffordable", poor, "InsufficientFunds")

	t:errs(
		"unknown upgrade is refused",
		state.act(USER, { kind = "BuyUpgrade", upgradeId = "nope" }),
		"UnknownUpgrade"
	)
	t:errs(
		"rebirth below the threshold is refused",
		state.act(USER, { kind = "Rebirth" }),
		"RebirthNotAffordable"
	)

	-- Receipts: granted once, acknowledged forever after.
	local product = { id = "starter", productId = 1, grant = { currency = "coins", amount = 500 } }
	deps.config.products = { product }
	local before = server:profileOf(USER).wallet.coins
	t:check("first receipt is granted", state.receipt(USER, "starter", "receipt-1") == true)
	t:eq("grant lands in the wallet", server:profileOf(USER).wallet.coins, before + 500)
	t:check("receipt is forced to disk before acknowledging", state.saved > 0)
	t:check("repeat receipt is acknowledged", state.receipt(USER, "starter", "receipt-1") == true)
	t:eq("repeat receipt grants nothing", server:profileOf(USER).wallet.coins, before + 500)
	t:check("unknown product is not acknowledged", state.receipt(USER, "ghost", "receipt-2") == false)

	state.leave(USER)
	t:eq("leaving drops the profile", server:profileOf(USER), nil)
	t:check("leaving forces a save", state.saved >= 2)
	t:check("leaving releases the session", state.released)

	t:errs("actions without a profile are refused", state.act(USER, { kind = "Rebirth" }), "ProfileNotLoaded")

	-- A refused write must end the session, not keep a balance nobody is recording.
	local lost, lostDeps = fakes(config)
	local lostServer = Runtime.server(lostDeps)
	lostServer:start()
	lost.join(USER)
	lost.syncFails = true
	lost.ticks[1].handler()
	t:eq("a refused sync drops the profile", lostServer:profileOf(USER), nil)
	t:check("a refused sync kicks the player", lost.kicked ~= nil)

	-- An unconfirmed save must leave the receipt unacknowledged AND undo the grant, or
	-- Roblox resends it and the player is paid twice.
	local unpaid, unpaidDeps = fakes(config)
	local unpaidServer = Runtime.server(unpaidDeps)
	unpaidServer:start()
	unpaid.join(USER)
	unpaidDeps.config.products = { product }
	unpaid.saveFails = true
	local balanceBefore = unpaidServer:profileOf(USER).wallet.coins
	t:check("an unconfirmed save is not acknowledged", unpaid.receipt(USER, "starter", "r-1") == false)
	t:eq("the failed grant is rolled back", unpaidServer:profileOf(USER).wallet.coins, balanceBefore)

	-- A locked save must kick, not silently drop the player into an unsaved session.
	local locked, lockedDeps = fakes(config)
	locked.loadResult = { ok = false, code = "ProfileLocked", message = "held" }
	local lockedServer = Runtime.server(lockedDeps)
	lockedServer:start()
	locked.join(USER)
	t:check("locked profile kicks the player", locked.kicked ~= nil)
	t:eq("no profile is kept after a kick", lockedServer:profileOf(USER), nil)
end

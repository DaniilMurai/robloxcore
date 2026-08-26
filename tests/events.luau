--!strict

local Events = require("../src/logic/events")

local function newProfile(coins: number, rebirths: number)
	return {
		schemaVersion = 1,
		wallet = { coins = coins },
		upgrades = {},
		rebirths = rebirths,
		processedReceipts = {},
		stats = { firstJoinAt = 0, lastSeenAt = 0, playtimeSeconds = 0, totalEarned = {} },
	}
end

return function(t)
	local profile = newProfile(120, 2)

	local spent = Events.economy(profile, "coins", -30, "Shop")
	t:eq("negative delta is a sink", spent.flowType, "Sink")
	t:eq("amount is reported unsigned", spent.amount, 30)
	t:eq("ending balance comes from the profile", spent.endingBalance, 120)
	t:eq("reason becomes the transaction type", spent.transactionType, "Shop")
	t:eq("currency is carried through", spent.currencyType, "coins")

	local gained = Events.economy(profile, "coins", 30, "Gameplay")
	t:eq("positive delta is a source", gained.flowType, "Source")

	local missing = Events.economy(profile, "gems", 5, "Gameplay")
	t:eq("unknown currency reports a zero balance", missing.endingBalance, 0)

	local milestone = Events.progression(profile, "conveyor", 3)
	t:eq("path names the upgrade", milestone.progressionPathName, "upgrade:conveyor")
	t:eq("upgrade levels are milestones", milestone.status, "Complete")
	t:eq("level is carried through", milestone.level, 3)
	t:eq("level name carries the rebirth cycle", milestone.levelName, "rebirth 2")
end

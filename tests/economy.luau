--!strict

local Economy = require("../src/logic/economy")
local Config = require("../src/logic/config")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local function newProfile(wallet: { [string]: number }, upgrades: { [string]: number }, rebirths: number)
	return {
		schemaVersion = 1,
		wallet = wallet,
		upgrades = upgrades,
		rebirths = rebirths,
		processedReceipts = {},
		stats = {
			firstJoinAt = 0,
			lastSeenAt = 0,
			playtimeSeconds = 0,
			totalEarned = {},
		},
	}
end

return function(t)
	local fixture = serde.decode("json", fs.readFile("tests/fixtures/main.json"))
	local validated = Config.validate(fixture)
	assert(validated.ok, "fixture config must validate")
	local config = validated.value
	local upgradeDef = config.upgrades[1]

	-- upgradeCost / totalCostToLevel

	t:eq("upgradeCost at level 0 is baseCost", Economy.upgradeCost(upgradeDef, 0), 25)
	t:eq(
		"upgradeCost grows geometrically by growth",
		Economy.upgradeCost(upgradeDef, 1),
		math.floor(25 * 1.35)
	)

	local expectedTotal = 0
	for level = 0, 3 - 1 do
		expectedTotal += Economy.upgradeCost(upgradeDef, level)
	end
	t:eq(
		"totalCostToLevel(def, 3) sums upgradeCost over levels 0..2",
		Economy.totalCostToLevel(upgradeDef, 3),
		expectedTotal
	)
	t:check("totalCostToLevel sum is not a shortcut formula result", expectedTotal > 0)

	-- spend: insufficient funds

	local poor = newProfile({ coins = 10 }, {}, 0)
	local spendResult = Economy.spend(poor, "coins", 25)
	t:errs("spend more than balance is InsufficientFunds", spendResult, "InsufficientFunds")
	t:eq("spend does not mutate input profile balance", poor.wallet.coins, 10)

	-- spend: unknown currency

	local unknownSpend = Economy.spend(poor, "gems", 5)
	t:errs("spend with unknown currency is UnknownCurrency", unknownSpend, "UnknownCurrency")

	-- earn: unknown currency

	local unknownEarn = Economy.earn(poor, "gems", 5)
	t:errs("earn with unknown currency is UnknownCurrency", unknownEarn, "UnknownCurrency")

	-- earn: does not mutate input, returns a new profile

	local earnBase = newProfile({ coins = 10 }, {}, 0)
	local earned = Economy.earn(earnBase, "coins", 5)
	t:check("earn succeeds", earned.ok)
	if earned.ok then
		t:eq("earn adds to the new profile's balance", earned.value.wallet.coins, 15)
	end
	t:eq("earn does not mutate input profile balance", earnBase.wallet.coins, 10)
	if earned.ok then
		t:eq("earn accumulates lifetime totals", earned.value.stats.totalEarned.coins, 5)
	end
	t:eq("earn does not mutate input lifetime totals", earnBase.stats.totalEarned.coins, nil)

	local negative = pcall(function()
		Economy.earn(earnBase, "coins", -5)
	end)
	t:check("earn with a negative amount raises error()", not negative)

	-- incomePerSecond: baseline vs upgrade flat effect

	local noUpgrades = newProfile({ coins = 0 }, {}, 0)
	local baseline = Economy.incomePerSecond(noUpgrades, config, {})
	t:eq("incomePerSecond with no upgrades equals baseIncomePerSecond", baseline, config.baseIncomePerSecond)

	local withUpgrade = newProfile({ coins = 0 }, { conveyor = 3 }, 0)
	local flatIncome = Economy.incomePerSecond(withUpgrade, config, {})
	t:eq(
		"IncomeFlat effect adds perLevel * level",
		flatIncome,
		config.baseIncomePerSecond + upgradeDef.effect.perLevel * 3
	)

	-- incomePerSecond: pass multiplier increases income and is not stored anywhere

	local withPass = Economy.incomePerSecond(withUpgrade, config, { "double_coins" })
	t:check("incomePerSecond with an owned pass exceeds income without it", withPass > flatIncome)
	t:eq("owning a pass does not touch the profile's wallet", withUpgrade.wallet.coins, 0)
	t:eq("owning a pass does not add fields to the profile", withUpgrade.upgrades.conveyor, 3)

	local passDef = config.passes[1]
	t:eq(
		"IncomeMultiplier effect from a pass multiplies flat income",
		withPass,
		flatIncome * passDef.effect.perLevel
	)

	-- rebirth multiplier: grows with rebirths, capped at multiplierCap

	local mult0 = Economy.rebirthMultiplier(config, 0)
	local mult1 = Economy.rebirthMultiplier(config, 1)
	t:check("rebirth multiplier grows with rebirths", mult1 > mult0)
	t:eq("rebirth multiplier at 0 rebirths is 1", mult0, 1)

	local hugeRebirths = math.ceil(config.rebirth.multiplierCap / config.rebirth.multiplierPerRebirth) + 10
	local capped = Economy.rebirthMultiplier(config, hugeRebirths)
	t:eq("rebirth multiplier is capped at multiplierCap", capped, config.rebirth.multiplierCap)

	local withRebirth = newProfile({ coins = 0 }, {}, 1)
	local rebirthIncome = Economy.incomePerSecond(withRebirth, config, {})
	t:check("incomePerSecond scales with the rebirth multiplier", rebirthIncome > baseline)
end

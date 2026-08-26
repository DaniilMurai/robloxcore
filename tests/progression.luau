--!strict

local Progression = require("../src/logic/progression")
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
		processedReceipts = { some_receipt = 42 },
		stats = {
			firstJoinAt = 1,
			lastSeenAt = 2,
			playtimeSeconds = 3,
			totalEarned = { coins = 4 },
		},
	}
end

return function(t)
	local fixture = serde.decode("json", fs.readFile("tests/fixtures/main.json"))
	local validated = Config.validate(fixture)
	assert(validated.ok, "fixture config must validate")
	local config = validated.value
	local upgradeDef = config.upgrades[1]

	-- buyUpgrade: unknown id

	local unknownProfile = newProfile({ coins = 1000 }, {}, 0)
	local unknownResult = Progression.buyUpgrade(unknownProfile, config, "does_not_exist")
	t:errs("buyUpgrade with unknown id is UnknownUpgrade", unknownResult, "UnknownUpgrade")

	-- buyUpgrade: at maxLevel

	local maxedProfile = newProfile({ coins = 1000000 }, { conveyor = upgradeDef.maxLevel }, 0)
	local maxedResult = Progression.buyUpgrade(maxedProfile, config, "conveyor")
	t:errs("buyUpgrade at maxLevel is MaxLevelReached", maxedResult, "MaxLevelReached")

	-- buyUpgrade: insufficient funds, input untouched

	local poorProfile = newProfile({ coins = 1 }, {}, 0)
	local poorResult = Progression.buyUpgrade(poorProfile, config, "conveyor")
	t:errs("buyUpgrade without enough coins is InsufficientFunds", poorResult, "InsufficientFunds")
	t:eq("buyUpgrade failure does not mutate input wallet", poorProfile.wallet.coins, 1)
	t:eq("buyUpgrade failure does not mutate input upgrades", poorProfile.upgrades.conveyor, nil)

	-- buyUpgrade: success spends exactly upgradeCost and raises level by 1

	local richProfile = newProfile({ coins = 1000 }, { conveyor = 2 }, 0)
	local costAtLevel2 = Economy.upgradeCost(upgradeDef, 2)
	local bought = Progression.buyUpgrade(richProfile, config, "conveyor")
	t:check("buyUpgrade succeeds with enough funds", bought.ok)
	if bought.ok then
		t:eq(
			"buyUpgrade spends exactly upgradeCost(def, levelBeforeBuy)",
			bought.value.wallet.coins,
			1000 - costAtLevel2
		)
		t:eq("buyUpgrade raises the level by 1", bought.value.upgrades.conveyor, 3)
	end
	t:eq("buyUpgrade does not mutate input wallet", richProfile.wallet.coins, 1000)
	t:eq("buyUpgrade does not mutate input upgrades", richProfile.upgrades.conveyor, 2)

	-- rebirthCost matches the floor(base * growth^rebirths) form

	local requirement = config.rebirth.requirement
	t:eq(
		"rebirthCost at 0 rebirths equals base",
		Progression.rebirthCost(config, 0),
		math.floor(requirement.base * requirement.growth ^ 0)
	)
	t:eq(
		"rebirthCost grows geometrically by growth",
		Progression.rebirthCost(config, 2),
		math.floor(requirement.base * requirement.growth ^ 2)
	)

	-- canRebirth: false below threshold, true exactly at threshold

	local threshold = Progression.rebirthCost(config, 0)
	local belowThreshold = newProfile({ coins = threshold - 1 }, {}, 0)
	t:eq("canRebirth is false below the threshold", Progression.canRebirth(belowThreshold, config), false)

	local atThreshold = newProfile({ coins = threshold }, {}, 0)
	t:eq("canRebirth is true exactly at the threshold", Progression.canRebirth(atThreshold, config), true)

	-- rebirth: below threshold is RebirthNotAffordable

	local notAffordable = Progression.rebirth(belowThreshold, config)
	t:errs("rebirth below the threshold is RebirthNotAffordable", notAffordable, "RebirthNotAffordable")

	-- rebirth: success resets exactly what resets lists, bumps rebirths, leaves the rest alone

	local rebirthProfile = newProfile({ coins = threshold }, { conveyor = 5 }, 0)
	local rebirthed = Progression.rebirth(rebirthProfile, config)
	t:check("rebirth succeeds at the threshold", rebirthed.ok)
	if rebirthed.ok then
		local value = rebirthed.value
		t:eq("rebirth increments rebirths by 1", value.rebirths, 1)
		t:eq(
			"rebirth resets the threshold currency to its starting balance",
			value.wallet.coins,
			config.currencies[1].starting
		)
		t:eq("rebirth resets upgrades listed in resets", value.upgrades.conveyor, nil)
		t:eq("rebirth does not touch stats", value.stats.totalEarned.coins, 4)
		t:eq("rebirth does not touch processedReceipts", value.processedReceipts.some_receipt, 42)
	end
	t:eq("rebirth does not mutate input wallet", rebirthProfile.wallet.coins, threshold)
	t:eq("rebirth does not mutate input upgrades", rebirthProfile.upgrades.conveyor, 5)
	t:eq("rebirth does not mutate input rebirths", rebirthProfile.rebirths, 0)

	-- rebirth with a currency not listed in resets survives (uses a config copy, not the fixture file)

	local extraConfig = table.clone(config) :: any
	extraConfig.currencies =
		{ config.currencies[1], { id = "gems", name = "Gems", short = "g", starting = 3 } }
	extraConfig.rebirth = table.clone(config.rebirth)
	extraConfig.rebirth.resets = { "coins", "upgrades" }
	local survivorProfile = newProfile({ coins = threshold, gems = 99 }, {}, 0)
	local survivorRebirth = Progression.rebirth(survivorProfile, extraConfig)
	t:check("rebirth with an extra currency succeeds", survivorRebirth.ok)
	if survivorRebirth.ok then
		t:eq("currency not listed in resets is untouched by rebirth", survivorRebirth.value.wallet.gems, 99)
	end

	-- rebirthMultiplier: re-exports Economy.rebirthMultiplier, capped at multiplierCap

	t:eq(
		"rebirthMultiplier matches Economy.rebirthMultiplier",
		Progression.rebirthMultiplier(config, 3),
		Economy.rebirthMultiplier(config, 3)
	)

	local hugeRebirths = math.ceil(config.rebirth.multiplierCap / config.rebirth.multiplierPerRebirth) + 10
	t:eq(
		"rebirthMultiplier is capped at multiplierCap for a large rebirth count",
		Progression.rebirthMultiplier(config, hugeRebirths),
		config.rebirth.multiplierCap
	)
end

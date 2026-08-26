--!strict

local Config = require("../src/logic/config")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(t)
	local fixture = serde.decode("json", fs.readFile("tests/fixtures/main.json"))

	local valid = Config.validate(fixture)
	t:check("valid fixture is ok", valid.ok, if not valid.ok then valid.message else nil)

	-- missing required field
	local missingRebirth = table.clone(fixture)
	missingRebirth.rebirth = nil
	local missing = Config.validate(missingRebirth)
	t:errs("missing rebirth is ConfigInvalid", missing, "ConfigInvalid")
	t:check(
		"missing rebirth message names the field",
		not missing.ok and missing.message:find("rebirth", 1, true) ~= nil,
		not missing.ok and missing.message or nil
	)

	-- wrong type
	local wrongType = table.clone(fixture)
	wrongType.baseIncomePerSecond = "one"
	local badType = Config.validate(wrongType)
	t:errs("wrong type is ConfigInvalid", badType, "ConfigInvalid")
	t:check(
		"wrong type message names the field",
		not badType.ok and badType.message:find("baseIncomePerSecond", 1, true) ~= nil,
		not badType.ok and badType.message or nil
	)

	-- growth <= 1.0
	local flatGrowth = table.clone(fixture)
	flatGrowth.upgrades = { table.clone(fixture.upgrades[1]) }
	flatGrowth.upgrades[1].growth = 1
	local badGrowth = Config.validate(flatGrowth)
	t:errs("growth <= 1.0 is ConfigInvalid", badGrowth, "ConfigInvalid")
	t:check(
		"growth message names the field",
		not badGrowth.ok and badGrowth.message:find("growth", 1, true) ~= nil,
		not badGrowth.ok and badGrowth.message or nil
	)

	-- unknown currency reference
	local badRef = table.clone(fixture)
	badRef.upgrades = { table.clone(fixture.upgrades[1]) }
	badRef.upgrades[1].currency = "gems"
	local unknownCurrency = Config.validate(badRef)
	t:errs("unknown currency reference is ConfigInvalid", unknownCurrency, "ConfigInvalid")
	t:check(
		"unknown currency message names the field",
		not unknownCurrency.ok and unknownCurrency.message:find("currency", 1, true) ~= nil,
		not unknownCurrency.ok and unknownCurrency.message or nil
	)

	-- duplicate id
	local dup = table.clone(fixture)
	dup.currencies = { fixture.currencies[1], fixture.currencies[1] }
	local duplicate = Config.validate(dup)
	t:errs("duplicate currency id is ConfigInvalid", duplicate, "ConfigInvalid")
	t:check(
		"duplicate id message names the field",
		not duplicate.ok and duplicate.message:find("id", 1, true) ~= nil,
		not duplicate.ok and duplicate.message or nil
	)

	-- rebirth threshold currency must be reset, otherwise rebirth is repeatable for free
	local noResetForThreshold = table.clone(fixture)
	noResetForThreshold.rebirth = table.clone(fixture.rebirth)
	noResetForThreshold.rebirth.resets = { "upgrades" }
	local missingReset = Config.validate(noResetForThreshold)
	t:errs("rebirth currency missing from resets is ConfigInvalid", missingReset, "ConfigInvalid")
	t:check(
		"missing reset message names the field",
		not missingReset.ok and missingReset.message:find("resets", 1, true) ~= nil,
		not missingReset.ok and missingReset.message or nil
	)

	-- ranges: a config can be well-shaped and still describe a broken economy
	local function broken(mutate)
		local copy = serde.decode("json", serde.encode("json", fixture))
		mutate(copy)
		return Config.validate(copy)
	end

	local negativeStart = broken(function(c)
		c.currencies[1].starting = -100
	end)
	t:errs("negative starting balance is refused", negativeStart, "ConfigInvalid")
	t:check(
		"negative starting message names the field",
		not negativeStart.ok and negativeStart.message:find("starting", 1, true) ~= nil
	)

	t:errs(
		"empty currencies is refused",
		broken(function(c)
			c.currencies = {}
		end),
		"ConfigInvalid"
	)
	t:errs(
		"zero baseCost is refused",
		broken(function(c)
			c.upgrades[1].baseCost = 0
		end),
		"ConfigInvalid"
	)
	t:errs(
		"maxLevel below one is refused",
		broken(function(c)
			c.upgrades[1].maxLevel = 0
		end),
		"ConfigInvalid"
	)
	t:errs(
		"multiplierCap below one is refused",
		broken(function(c)
			c.rebirth.multiplierCap = 0.5
		end),
		"ConfigInvalid"
	)
	t:errs(
		"negative multiplierPerRebirth is refused",
		broken(function(c)
			c.rebirth.multiplierPerRebirth = -1
		end),
		"ConfigInvalid"
	)
	t:errs(
		"zero rebirth threshold is refused",
		broken(function(c)
			c.rebirth.requirement.base = 0
		end),
		"ConfigInvalid"
	)

	t:errs(
		"missing world is refused",
		broken(function(c)
			c.world = nil
		end),
		"ConfigInvalid"
	)
	t:errs(
		"missing world part is refused",
		broken(function(c)
			c.world.collector = nil
		end),
		"ConfigInvalid"
	)
	t:errs(
		"two-component size is refused",
		broken(function(c)
			c.world.platform.size = { 40, 1 }
		end),
		"ConfigInvalid"
	)
	t:errs(
		"zero size is refused",
		broken(function(c)
			c.world.conveyor.size[1] = 0
		end),
		"ConfigInvalid"
	)
	-- 0..255 is the other common way to spell a colour, and it would silently clip to white
	t:errs(
		"colour outside 0..1 is refused",
		broken(function(c)
			c.world.dropper.color = { 220, 120, 40 }
		end),
		"ConfigInvalid"
	)
	local badMaterial = broken(function(c)
		c.world.platform.material = 7
	end)
	t:errs("non-string material is refused", badMaterial, "ConfigInvalid")
	t:check(
		"world message names the failing field",
		not badMaterial.ok and badMaterial.message:find("world.platform.material", 1, true) ~= nil,
		not badMaterial.ok and badMaterial.message or nil
	)

	t:errs(
		"a free zone is refused",
		broken(function(c)
			c.zones[1].cost = 0
		end),
		"ConfigInvalid"
	)
	t:errs(
		"a zone in an unknown currency is refused",
		broken(function(c)
			c.zones[1].currency = "gems"
		end),
		"ConfigInvalid"
	)
	t:errs(
		"a zone unlocking an unknown upgrade is refused",
		broken(function(c)
			c.zones[1].unlocks = { "no_such_upgrade" }
		end),
		"ConfigInvalid"
	)
	-- Two gates on one upgrade leave the player no way to know which zone to buy
	t:errs(
		"two zones gating one upgrade are refused",
		broken(function(c)
			c.zones[2].unlocks = { "slicer" }
		end),
		"ConfigInvalid"
	)
	t:errs(
		"a duplicated zone id is refused",
		broken(function(c)
			c.zones[2].id = c.zones[1].id
			c.zones[2].unlocks = {}
		end),
		"ConfigInvalid"
	)
	t:errs(
		"a two-component zone position is refused",
		broken(function(c)
			c.zones[1].position = { 5, 0 }
		end),
		"ConfigInvalid"
	)

	-- original fixture is untouched by validation and by the shallow clones above
	t:eq("validate does not mutate the raw table", fixture.rebirth ~= nil, true)
	t:eq("validate does not mutate upgrades growth", fixture.upgrades[1].growth, 1.35)
end

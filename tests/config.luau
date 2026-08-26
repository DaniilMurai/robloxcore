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

	-- original fixture is untouched by validation and by the shallow clones above
	t:eq("validate does not mutate the raw table", fixture.rebirth ~= nil, true)
	t:eq("validate does not mutate upgrades growth", fixture.upgrades[1].growth, 1.35)
end

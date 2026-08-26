--!strict
-- The only door raw JSON takes into the game: everything downstream trusts a
-- TitleConfig produced here instead of re-checking shapes.

local Types = require("./types")
local Result = require("./result")

type TitleConfig = Types.TitleConfig
type Result<T> = Result.Result<T>

local VALID_EFFECT_KINDS: { [string]: true } = {
	IncomeMultiplier = true,
	IncomeFlat = true,
	WalkSpeed = true,
	Capacity = true,
}

local function fail(message: string): Result<TitleConfig>
	return Result.err("ConfigInvalid", message)
end

local function isString(v: any): boolean
	return type(v) == "string" and v ~= ""
end

local function isNumber(v: any): boolean
	return type(v) == "number"
end

local function isTable(v: any): boolean
	return type(v) == "table"
end

-- Validates {kind, perLevel} shared by upgrades and passes.
local function validateEffect(effect: any, path: string): string?
	if type(effect) ~= "table" then
		return ("%s.effect must be a table, got %s"):format(path, type(effect))
	end
	if not isString(effect.kind) then
		return ("%s.effect.kind must be a string"):format(path)
	end
	if not VALID_EFFECT_KINDS[effect.kind] then
		return ("%s.effect.kind must be one of IncomeMultiplier|IncomeFlat|WalkSpeed|Capacity, got %s"):format(
			path,
			tostring(effect.kind)
		)
	end
	if not isNumber(effect.perLevel) then
		return ("%s.effect.perLevel must be a number"):format(path)
	end
	return nil
end

local function validate(raw: any): Result<TitleConfig>
	if type(raw) ~= "table" then
		return fail(("config must be a table, got %s"):format(type(raw)))
	end

	if not isString(raw.slug) then
		return fail("slug must be a non-empty string")
	end
	if not isString(raw.displayName) then
		return fail("displayName must be a non-empty string")
	end
	if not isNumber(raw.baseIncomePerSecond) then
		return fail("baseIncomePerSecond must be a number")
	end

	if not isTable(raw.currencies) then
		return fail("currencies must be an array")
	end
	local currencyIds: { [string]: true } = {}
	for i, currency in raw.currencies :: any do
		local path = ("currencies[%d]"):format(i)
		if type(currency) ~= "table" then
			return fail(("%s must be a table, got %s"):format(path, type(currency)))
		end
		if not isString(currency.id) then
			return fail(("%s.id must be a non-empty string"):format(path))
		end
		if not isString(currency.name) then
			return fail(("%s.name must be a non-empty string"):format(path))
		end
		if not isString(currency.short) then
			return fail(("%s.short must be a non-empty string"):format(path))
		end
		if not isNumber(currency.starting) then
			return fail(("%s.starting must be a number"):format(path))
		end
		if currencyIds[currency.id] then
			return fail(("%s.id %q is duplicated"):format(path, currency.id))
		end
		currencyIds[currency.id] = true
	end

	if not isTable(raw.upgrades) then
		return fail("upgrades must be an array")
	end
	local upgradeIds: { [string]: true } = {}
	for i, upgrade in raw.upgrades :: any do
		local path = ("upgrades[%d]"):format(i)
		if type(upgrade) ~= "table" then
			return fail(("%s must be a table, got %s"):format(path, type(upgrade)))
		end
		if not isString(upgrade.id) then
			return fail(("%s.id must be a non-empty string"):format(path))
		end
		if not isString(upgrade.name) then
			return fail(("%s.name must be a non-empty string"):format(path))
		end
		if not isString(upgrade.currency) then
			return fail(("%s.currency must be a non-empty string"):format(path))
		end
		if not currencyIds[upgrade.currency] then
			return fail(("%s.currency references unknown currency %q"):format(path, upgrade.currency))
		end
		if not isNumber(upgrade.baseCost) then
			return fail(("%s.baseCost must be a number"):format(path))
		end
		if not isNumber(upgrade.growth) then
			return fail(("%s.growth must be a number"):format(path))
		end
		if upgrade.growth <= 1.0 then
			return fail(("%s.growth must be > 1.0, got %s"):format(path, tostring(upgrade.growth)))
		end
		if not isNumber(upgrade.maxLevel) then
			return fail(("%s.maxLevel must be a number"):format(path))
		end
		local effectErr = validateEffect(upgrade.effect, path)
		if effectErr then
			return fail(effectErr)
		end
		if upgradeIds[upgrade.id] then
			return fail(("%s.id %q is duplicated"):format(path, upgrade.id))
		end
		upgradeIds[upgrade.id] = true
	end

	if type(raw.rebirth) ~= "table" then
		return fail("rebirth must be a table")
	end
	local rebirth = raw.rebirth
	if type(rebirth.requirement) ~= "table" then
		return fail("rebirth.requirement must be a table")
	end
	if not isString(rebirth.requirement.currency) then
		return fail("rebirth.requirement.currency must be a non-empty string")
	end
	if not currencyIds[rebirth.requirement.currency] then
		return fail(
			("rebirth.requirement.currency references unknown currency %q"):format(
				rebirth.requirement.currency
			)
		)
	end
	if not isNumber(rebirth.requirement.base) then
		return fail("rebirth.requirement.base must be a number")
	end
	if not isNumber(rebirth.requirement.growth) then
		return fail("rebirth.requirement.growth must be a number")
	end
	if rebirth.requirement.growth <= 1.0 then
		return fail(
			("rebirth.requirement.growth must be > 1.0, got %s"):format(tostring(rebirth.requirement.growth))
		)
	end
	if not isNumber(rebirth.multiplierPerRebirth) then
		return fail("rebirth.multiplierPerRebirth must be a number")
	end
	if not isNumber(rebirth.multiplierCap) then
		return fail("rebirth.multiplierCap must be a number")
	end
	if not isTable(rebirth.resets) then
		return fail("rebirth.resets must be an array")
	end
	for i, reset in rebirth.resets :: any do
		local path = ("rebirth.resets[%d]"):format(i)
		if not isString(reset) then
			return fail(("%s must be a non-empty string"):format(path))
		end
		if reset ~= "upgrades" and not currencyIds[reset] then
			return fail(('%s must be "upgrades" or an existing currency, got %q'):format(path, reset))
		end
	end

	if not isTable(raw.passes) then
		return fail("passes must be an array")
	end
	local passIds: { [string]: true } = {}
	for i, pass in raw.passes :: any do
		local path = ("passes[%d]"):format(i)
		if type(pass) ~= "table" then
			return fail(("%s must be a table, got %s"):format(path, type(pass)))
		end
		if not isString(pass.id) then
			return fail(("%s.id must be a non-empty string"):format(path))
		end
		if not isNumber(pass.gamepassId) then
			return fail(("%s.gamepassId must be a number"):format(path))
		end
		local effectErr = validateEffect(pass.effect, path)
		if effectErr then
			return fail(effectErr)
		end
		if passIds[pass.id] then
			return fail(("%s.id %q is duplicated"):format(path, pass.id))
		end
		passIds[pass.id] = true
	end

	if not isTable(raw.products) then
		return fail("products must be an array")
	end
	local productIds: { [string]: true } = {}
	for i, product in raw.products :: any do
		local path = ("products[%d]"):format(i)
		if type(product) ~= "table" then
			return fail(("%s must be a table, got %s"):format(path, type(product)))
		end
		if not isString(product.id) then
			return fail(("%s.id must be a non-empty string"):format(path))
		end
		if not isNumber(product.productId) then
			return fail(("%s.productId must be a number"):format(path))
		end
		if type(product.grant) ~= "table" then
			return fail(("%s.grant must be a table"):format(path))
		end
		if not isString(product.grant.currency) then
			return fail(("%s.grant.currency must be a non-empty string"):format(path))
		end
		if not currencyIds[product.grant.currency] then
			return fail(
				("%s.grant.currency references unknown currency %q"):format(path, product.grant.currency)
			)
		end
		if not isNumber(product.grant.amount) then
			return fail(("%s.grant.amount must be a number"):format(path))
		end
		if productIds[product.id] then
			return fail(("%s.id %q is duplicated"):format(path, product.id))
		end
		productIds[product.id] = true
	end

	return Result.ok(raw :: TitleConfig)
end

return { validate = validate }

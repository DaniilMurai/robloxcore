--!strict
-- Ported from slice/src/logic/economy.luau under the contract's typed signatures.
-- buyUpgrade stays out on purpose: contracts.md assigns it to Progression (T-05).

local Types = require("./types")
local Result = require("./result")

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type UpgradeDef = Types.UpgradeDef
type Result<T> = Result.Result<T>

local Economy = {}

function Economy.upgradeCost(def: UpgradeDef, level: number): number
	return math.floor(def.baseCost * def.growth ^ level)
end

function Economy.totalCostToLevel(def: UpgradeDef, targetLevel: number): number
	local total = 0
	for level = 0, targetLevel - 1 do
		total += Economy.upgradeCost(def, level)
	end
	return total
end

function Economy.findUpgrade(config: TitleConfig, upgradeId: string): UpgradeDef?
	for _, def in config.upgrades do
		if def.id == upgradeId then
			return def
		end
	end
	return nil
end

-- Not in contracts.md's public surface: progression.luau (T-05) cannot require economy.luau
-- and vice versa (buyUpgrade there calls Economy.spend), so the rebirth multiplier formula
-- lives here and Progression.rebirthMultiplier becomes a thin re-export.
function Economy.rebirthMultiplier(config: TitleConfig, rebirths: number): number
	local multiplier = 1 + config.rebirth.multiplierPerRebirth * rebirths
	return math.min(multiplier, config.rebirth.multiplierCap)
end

-- Pass effects are derived from live ownership, never stored in the profile: that is what
-- makes a re-join unable to grant the same multiplier twice.
function Economy.incomePerSecond(profile: ProfileData, config: TitleConfig, ownedPassIds: { string }): number
	local flat = config.baseIncomePerSecond
	local multiplier = 1

	for _, def in config.upgrades do
		local level = profile.upgrades[def.id] or 0
		if def.effect.kind == "IncomeFlat" then
			flat += def.effect.perLevel * level
		elseif def.effect.kind == "IncomeMultiplier" then
			multiplier *= def.effect.perLevel ^ level
		end
	end

	local owned: { [string]: boolean } = {}
	for _, id in ownedPassIds do
		owned[id] = true
	end
	for _, def in config.passes do
		if owned[def.id] and def.effect.kind == "IncomeMultiplier" then
			multiplier *= def.effect.perLevel
		end
	end

	multiplier *= Economy.rebirthMultiplier(config, profile.rebirths)

	return flat * multiplier
end

function Economy.earn(profile: ProfileData, currencyId: string, amount: number): Result<ProfileData>
	if profile.wallet[currencyId] == nil then
		return Result.err("UnknownCurrency", currencyId)
	end
	-- A negative payout is a caller bug, not a domain refusal: silently turning it into an
	-- Err would let a broken income tick drain the wallet through the earn path.
	if amount < 0 then
		error(("Economy.earn: amount must be >= 0, got %d"):format(amount), 2)
	end

	local updated = table.clone(profile)
	updated.wallet = table.clone(profile.wallet)
	updated.wallet[currencyId] += amount
	updated.stats = table.clone(profile.stats)
	updated.stats.totalEarned = table.clone(profile.stats.totalEarned)
	updated.stats.totalEarned[currencyId] = (profile.stats.totalEarned[currencyId] or 0) + amount
	return Result.ok(updated)
end

function Economy.spend(profile: ProfileData, currencyId: string, amount: number): Result<ProfileData>
	local balance = profile.wallet[currencyId]
	if balance == nil then
		return Result.err("UnknownCurrency", currencyId)
	end
	if amount > balance then
		return Result.err("InsufficientFunds", ("balance=%d cost=%d"):format(balance, amount))
	end
	local updated = table.clone(profile)
	updated.wallet = table.clone(profile.wallet)
	updated.wallet[currencyId] -= amount
	return Result.ok(updated)
end

return Economy

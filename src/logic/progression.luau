--!strict
-- Upgrades and rebirth. Depends on economy.luau only (never the other way around,
-- see economy.luau's note on why rebirthMultiplier lives there instead of here).

local Types = require("./types")
local Result = require("./result")
local Economy = require("./economy")

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type Result<T> = Result.Result<T>

local Progression = {}

-- Which zone keeps an upgrade shut, if any. Config.validate guarantees at most one, so
-- the first hit is the answer.
function Progression.gateOf(config: TitleConfig, upgradeId: string): string?
	for _, zone in config.zones do
		for _, gated in zone.unlocks do
			if gated == upgradeId then
				return zone.id
			end
		end
	end
	return nil
end

function Progression.findZone(config: TitleConfig, zoneId: string): Types.ZoneDef?
	for _, zone in config.zones do
		if zone.id == zoneId then
			return zone
		end
	end
	return nil
end

function Progression.buyZone(profile: ProfileData, config: TitleConfig, zoneId: string): Result<ProfileData>
	local def = Progression.findZone(config, zoneId)
	if not def then
		return Result.err("UnknownZone", zoneId)
	end
	-- Charging twice for the same zone is the one failure a player notices immediately.
	if profile.zones[zoneId] then
		return Result.err("ZoneAlreadyOwned", zoneId)
	end

	local spent = Economy.spend(profile, def.currency, def.cost)
	if not spent.ok then
		return spent
	end

	local updated = table.clone(spent.value)
	updated.zones = table.clone(spent.value.zones)
	updated.zones[zoneId] = true
	return Result.ok(updated)
end

function Progression.buyUpgrade(
	profile: ProfileData,
	config: TitleConfig,
	upgradeId: string
): Result<ProfileData>
	local def = Economy.findUpgrade(config, upgradeId)
	if not def then
		return Result.err("UnknownUpgrade", upgradeId)
	end

	local gate = Progression.gateOf(config, upgradeId)
	if gate and not profile.zones[gate] then
		return Result.err("UpgradeLocked", ("%s needs zone %s"):format(upgradeId, gate))
	end

	local level = profile.upgrades[upgradeId] or 0
	if level >= def.maxLevel then
		return Result.err("MaxLevelReached", ("%s is at level %d"):format(upgradeId, level))
	end

	local cost = Economy.upgradeCost(def, level)
	local spent = Economy.spend(profile, def.currency, cost)
	if not spent.ok then
		return spent
	end

	local updated = table.clone(spent.value)
	updated.upgrades = table.clone(spent.value.upgrades)
	updated.upgrades[upgradeId] = level + 1
	return Result.ok(updated)
end

function Progression.rebirthCost(config: TitleConfig, rebirths: number): number
	local requirement = config.rebirth.requirement
	return math.floor(requirement.base * requirement.growth ^ rebirths)
end

function Progression.canRebirth(profile: ProfileData, config: TitleConfig): boolean
	local balance = profile.wallet[config.rebirth.requirement.currency] or 0
	return balance >= Progression.rebirthCost(config, profile.rebirths)
end

function Progression.rebirth(profile: ProfileData, config: TitleConfig): Result<ProfileData>
	if not Progression.canRebirth(profile, config) then
		local shortfall = Progression.rebirthCost(config, profile.rebirths)
			- (profile.wallet[config.rebirth.requirement.currency] or 0)
		return Result.err("RebirthNotAffordable", ("need %d more"):format(shortfall))
	end

	local updated = table.clone(profile)
	updated.rebirths = profile.rebirths + 1
	updated.wallet = table.clone(profile.wallet)
	updated.upgrades = table.clone(profile.upgrades)

	-- The requirement currency is guaranteed to be in resets by Config.validate, so the
	-- threshold never needs a separate spend: it is zeroed out below along with everything
	-- else listed.
	for _, reset in config.rebirth.resets do
		if reset == "upgrades" then
			updated.upgrades = {}
		else
			local starting = 0
			for _, currency in config.currencies do
				if currency.id == reset then
					starting = currency.starting
					break
				end
			end
			updated.wallet[reset] = starting
		end
	end

	return Result.ok(updated)
end

function Progression.rebirthMultiplier(config: TitleConfig, rebirths: number): number
	return Economy.rebirthMultiplier(config, rebirths)
end

return Progression

--!strict
-- Shared data shapes from contracts.md. Forms only — economy/progression logic
-- lands in later tasks, this module has no behaviour beyond the type exports.

local SCHEMA_VERSION = 1 -- core's version; titles never override it

export type Wallet = { [string]: number } -- currencyId -> balance, >= 0
export type Upgrades = { [string]: number } -- upgradeId -> level, >= 0

export type ProfileData = {
	schemaVersion: number,
	wallet: Wallet,
	upgrades: Upgrades,
	rebirths: number, -- >= 0
	processedReceipts: { [string]: number }, -- receiptId -> os.time() of grant
	stats: {
		firstJoinAt: number, -- os.time(), UTC seconds
		lastSeenAt: number,
		playtimeSeconds: number,
		totalEarned: { [string]: number }, -- lifetime, for analytics and achievements
	},
}

export type CurrencyDef = { id: string, name: string, short: string, starting: number }

export type EffectKind = "IncomeMultiplier" | "IncomeFlat" | "WalkSpeed" | "Capacity"
export type Effect = { kind: EffectKind, perLevel: number }

export type UpgradeDef = {
	id: string,
	name: string,
	currency: string, -- id from currencies
	baseCost: number, -- cost of level 0 -> 1
	growth: number, -- geometric growth, > 1.0
	maxLevel: number,
	effect: Effect,
}

export type RebirthDef = {
	requirement: { currency: string, base: number, growth: number },
	multiplierPerRebirth: number,
	multiplierCap: number,
	resets: { string }, -- what gets zeroed out: currencyId and/or "upgrades"
}

-- Geometry reaches the pure layer as plain arrays: Vector3 and Color3 are Roblox globals,
-- and the AC-4 gate keeps them out of src/logic/. runtime/base.luau converts them.
export type PartStyle = {
	size: { number }, -- {x, y, z} in studs
	color: { number }, -- {r, g, b} in 0..1
	material: string, -- Enum.Material name
}

export type WorldDef = {
	platform: PartStyle,
	conveyor: PartStyle,
	dropper: PartStyle,
	collector: PartStyle,
	drop: PartStyle, -- one object on the belt; its colour is what level 0 looks like
}

export type PassDef = { id: string, gamepassId: number, effect: Effect }
export type ProductDef = { id: string, productId: number, grant: { currency: string, amount: number } }

-- Wire shapes. The client never sends amounts, only intent: every cost is recomputed
-- server-side from the config.
export type StateSnapshot = {
	wallet: Wallet,
	upgrades: Upgrades,
	rebirths: number,
	incomePerSecond: number,
	-- Ownership comes from the platform, never from the profile, so the client is told
	-- what the server currently sees instead of remembering anything itself.
	ownedPassIds: { string },
}

export type Action =
	{ kind: "BuyUpgrade", upgradeId: string }
	| { kind: "Rebirth" }
	| { kind: "PromptPass", passId: string }

export type TitleConfig = {
	slug: string,
	displayName: string,
	currencies: { CurrencyDef },
	baseIncomePerSecond: number,
	upgrades: { UpgradeDef },
	rebirth: RebirthDef,
	passes: { PassDef },
	products: { ProductDef },
	world: WorldDef,
}

return { SCHEMA_VERSION = SCHEMA_VERSION }

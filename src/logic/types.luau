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

export type PassDef = { id: string, gamepassId: number, effect: Effect }
export type ProductDef = { id: string, productId: number, grant: { currency: string, amount: number } }

-- Wire shapes. The client never sends amounts, only intent: every cost is recomputed
-- server-side from the config.
export type StateSnapshot = {
	wallet: Wallet,
	upgrades: Upgrades,
	rebirths: number,
	incomePerSecond: number,
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
}

return { SCHEMA_VERSION = SCHEMA_VERSION }

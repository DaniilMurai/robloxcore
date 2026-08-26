--!strict
-- Analytics payloads, assembled but never sent: the reporting service lives in the adapter
-- layer. Field names mirror LogEconomyEvent/LogProgressionEvent parameters so the adapter
-- is a straight hand-off, and the enum-shaped fields stay strings here — Enum.* is a
-- Roblox global the pure layer cannot touch.

local Types = require("./types")

type ProfileData = Types.ProfileData

export type EconomyFlow = "Sink" | "Source"
-- Mirrors Enum.AnalyticsProgressionType, whose items are Custom/Start/Fail/Complete.
export type ProgressionStatus = "Custom" | "Start" | "Fail" | "Complete"

export type EconomyEvent = {
	flowType: EconomyFlow,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
}

export type ProgressionEvent = {
	progressionPathName: string,
	status: ProgressionStatus,
	level: number,
	levelName: string,
}

local Events = {}

-- `profile` is the profile AFTER the change: endingBalance is what Roblox charts, and a
-- pre-change balance would silently shift every point on that chart by one transaction.
function Events.economy(profile: ProfileData, currencyId: string, delta: number, reason: string): EconomyEvent
	return {
		flowType = if delta < 0 then "Sink" else "Source",
		currencyType = currencyId,
		amount = math.abs(delta),
		endingBalance = profile.wallet[currencyId] or 0,
		transactionType = reason,
	}
end

-- Upgrade levels are milestones, not attempts, so every one is a Complete: there is no
-- failing path to report until the title grows one. The rebirth count rides along in
-- levelName because the same upgrade level means something different on each cycle.
function Events.progression(profile: ProfileData, upgradeId: string, level: number): ProgressionEvent
	return {
		progressionPathName = ("upgrade:%s"):format(upgradeId),
		status = "Complete",
		level = level,
		levelName = ("rebirth %d"):format(profile.rebirths),
	}
end

return Events

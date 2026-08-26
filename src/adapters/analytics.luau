--!strict
-- AnalyticsService wrapper. Titles never call it directly: the payloads are assembled in
-- src/logic/events.luau, and this module only maps the string fields onto Enum values.

local AnalyticsService = game:GetService("AnalyticsService")

local Events = require("../logic/events")

type EconomyEvent = Events.EconomyEvent
type ProgressionEvent = Events.ProgressionEvent

export type AnalyticsAdapter = {
	economy: (self: AnalyticsAdapter, player: Player, event: EconomyEvent) -> (),
	progression: (self: AnalyticsAdapter, player: Player, event: ProgressionEvent) -> (),
}

local AnalyticsAdapter = {}
AnalyticsAdapter.__index = AnalyticsAdapter

function AnalyticsAdapter.new(): AnalyticsAdapter
	return (setmetatable({}, AnalyticsAdapter) :: any) :: AnalyticsAdapter
end

-- Analytics is telemetry, not gameplay: a throw here must not take down the income tick
-- or the purchase that produced the event.
local function report(what: string, call: () -> ())
	local ok, err = pcall(call)
	if not ok then
		warn(`[analytics] {what} failed: {err}`)
	end
end

function AnalyticsAdapter:economy(player: Player, event: EconomyEvent)
	report("economy", function()
		AnalyticsService:LogEconomyEvent(
			player,
			(Enum.AnalyticsEconomyFlowType :: any)[event.flowType],
			event.currencyType,
			event.amount,
			event.endingBalance,
			event.transactionType
		)
	end)
end

function AnalyticsAdapter:progression(player: Player, event: ProgressionEvent)
	report("progression", function()
		AnalyticsService:LogProgressionEvent(
			player,
			event.progressionPathName,
			(Enum.AnalyticsProgressionType :: any)[event.status],
			event.level,
			event.levelName
		)
	end)
end

return AnalyticsAdapter

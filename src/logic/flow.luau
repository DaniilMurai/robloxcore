--!strict
-- What the belt shows, derived from what the player has bought. Cosmetics only: income
-- stays Economy.incomePerSecond and nothing here feeds back into it, because an object
-- that paid on arrival would make the balance depend on server lag.

local Types = require("./types")

local BASE_INTERVAL = 2.0 -- seconds between drops at level 0
local GAP_FACTOR = 3 -- centre-to-centre spacing, in object lengths
local HUE_STEP = 0.11 -- hue turn per upgrade level; wraps after nine

local Flow = {}

function Flow.level(profile: Types.ProfileData): number
	local total = 0
	for _, level in profile.upgrades do
		total += level
	end
	return total
end

-- The floor is spacing, not time: objects a fixed number of seconds apart still touch once
-- they are big enough or the belt is fast enough, and a belt of touching cubes reads as one
-- painted bar rather than a flow.
function Flow.minInterval(dropLength: number, studsPerSecond: number): number
	return dropLength * GAP_FACTOR / studsPerSecond
end

function Flow.interval(level: number, floor: number): number
	return math.max(BASE_INTERVAL / (1 + level), floor)
end

-- Objects alive at once cannot exceed this, whatever the level: the interval has a floor
-- and a drop lives exactly as long as the crossing. A longer belt legitimately holds more,
-- so the cap follows the belt instead of being a constant somebody has to keep in sync.
function Flow.liveCap(travelSeconds: number, floor: number): number
	return math.ceil(travelSeconds / floor) + 1
end

-- Streams sharing a belt each get their own lane across its depth. Without this, objects
-- from the base dropper and from every zone travel the same centre line and pile into one
-- another: three streams look exactly like one, only denser.
function Flow.lane(index: number, count: number, beltDepth: number, dropDepth: number): number
	if count <= 1 then
		return 0
	end
	local usable = math.max(beltDepth - dropDepth, 0)
	return -usable / 2 + usable * (index - 1) / (count - 1)
end

local function toHsv(rgb: { number }): (number, number, number)
	local r, g, b = rgb[1], rgb[2], rgb[3]
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local span = high - low
	local hue = 0
	if span > 0 then
		if high == r then
			hue = ((g - b) / span) % 6
		elseif high == g then
			hue = (b - r) / span + 2
		else
			hue = (r - g) / span + 4
		end
		hue /= 6
	end
	return hue, if high == 0 then 0 else span / high, high
end

local function fromHsv(hue: number, saturation: number, value: number): { number }
	local sector = hue * 6
	local span = value * saturation
	local rise = span * (1 - math.abs(sector % 2 - 1))
	local low = value - span
	local r, g, b
	if sector < 1 then
		r, g, b = span, rise, 0
	elseif sector < 2 then
		r, g, b = rise, span, 0
	elseif sector < 3 then
		r, g, b = 0, span, rise
	elseif sector < 4 then
		r, g, b = 0, rise, span
	elseif sector < 5 then
		r, g, b = rise, 0, span
	else
		r, g, b = span, 0, rise
	end
	return { r + low, g + low, b + low }
end

-- Hue only: turning saturation or value instead would eventually give a white or black
-- object, and an invisible drop is not a reward.
function Flow.tint(color: { number }, level: number): { number }
	local hue, saturation, value = toHsv(color)
	return fromHsv((hue + HUE_STEP * level) % 1, saturation, value)
end

return Flow

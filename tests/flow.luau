--!strict

local Flow = require("../src/logic/flow")

local function profile(upgrades: { [string]: number }): any
	return { upgrades = upgrades }
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return function(t)
	t:eq("no upgrades is level zero", Flow.level(profile({})), 0)
	t:eq("levels of every upgrade add up", Flow.level(profile({ conveyor = 3, oven = 2 })), 5)

	t:eq("level zero drops every two seconds", Flow.interval(0), 2)
	t:eq("first level halves the wait", Flow.interval(1), 1)
	t:check("the wait keeps shrinking", Flow.interval(4) < Flow.interval(3))
	-- The floor is what makes the live count bounded at all
	t:eq("a huge level still hits the floor", Flow.interval(10000), 0.2)

	t:eq("cap follows the crossing time", Flow.liveCap(3), 16)
	t:check("a longer belt holds more", Flow.liveCap(6) > Flow.liveCap(3))
	t:check("cap covers a full belt at the fastest rate", Flow.liveCap(3) >= 3 / Flow.interval(10000))

	local base = { 0.9, 0.75, 0.25 }
	local atZero = Flow.tint(base, 0)
	t:check(
		"level zero keeps the configured colour",
		near(atZero[1], base[1]) and near(atZero[2], base[2]) and near(atZero[3], base[3]),
		("%s"):format(table.concat(atZero, ", "))
	)

	local shifted = Flow.tint(base, 1)
	t:check(
		"a level moves the colour",
		not (near(shifted[1], base[1]) and near(shifted[2], base[2]) and near(shifted[3], base[3]))
	)

	local outOfRange = false
	for level = 0, 40 do
		for _, component in Flow.tint(base, level) do
			if component < 0 or component > 1 then
				outOfRange = true
			end
		end
	end
	t:check("every level stays inside 0..1", not outOfRange)

	-- Grey has no hue to turn, and a wrong conversion would invent one
	local grey = Flow.tint({ 0.5, 0.5, 0.5 }, 3)
	t:check(
		"grey stays grey",
		near(grey[1], 0.5) and near(grey[2], 0.5) and near(grey[3], 0.5),
		table.concat(grey, ", ")
	)
end

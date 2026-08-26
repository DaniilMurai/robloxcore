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

	-- 1.6-stud objects on an 8 studs/s belt: three lengths apart is 0.6 s
	local floor = Flow.minInterval(1.6, 8)
	t:check("the floor is a gap, measured in object lengths", near(floor, 0.6), tostring(floor))
	t:check("bigger objects need longer gaps", Flow.minInterval(3.2, 8) > floor)
	t:check("a faster belt needs shorter gaps", Flow.minInterval(1.6, 16) < floor)
	-- What Studio showed at the old fixed floor: spacing equalled the object itself, so the
	-- belt read as one painted bar instead of a line of objects.
	t:check("objects never touch at the floor", floor * 8 > 1.6)

	t:eq("level zero drops every two seconds", Flow.interval(0, floor), 2)
	t:eq("first level halves the wait", Flow.interval(1, floor), 1)
	t:check("the wait keeps shrinking", Flow.interval(2, floor) < Flow.interval(1, floor))
	t:eq("a huge level still hits the floor", Flow.interval(10000, floor), floor)

	t:eq("cap follows the crossing time", Flow.liveCap(3, floor), 6)
	t:check("a longer belt holds more", Flow.liveCap(6, floor) > Flow.liveCap(3, floor))
	t:check(
		"cap covers a full belt at the fastest rate",
		Flow.liveCap(3, floor) >= 3 / Flow.interval(10000, floor)
	)

	t:eq("a lone stream runs down the middle", Flow.lane(1, 1, 6, 1.6), 0)
	local firstLane, lastLane = Flow.lane(1, 3, 6, 1.6), Flow.lane(3, 3, 6, 1.6)
	t:eq("lanes are symmetric about the centre", firstLane, -lastLane)
	t:eq("the middle stream stays centred", Flow.lane(2, 3, 6, 1.6), 0)
	-- Objects have to stay on the belt, not hang over its edge
	t:check("the outer lane keeps the object on the belt", math.abs(firstLane) + 1.6 / 2 <= 6 / 2)
	t:check("neighbouring lanes do not overlap", math.abs(Flow.lane(2, 3, 6, 1.6) - firstLane) > 1.6)

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

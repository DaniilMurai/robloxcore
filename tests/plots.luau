--!strict

local Plots = require("../src/logic/plots")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(t)
	local world = (serde.decode("json", fs.readFile("tests/fixtures/main.json")) :: any).world

	-- 26-stud belt with a 4-stud dropper and a 6-stud collector reaches 36; the platform
	-- is 40, so the platform is what a neighbour has to clear.
	t:eq("footprint takes the wider of platform and belt line", Plots.footprint(world), 40)

	local wideBelt = {
		platform = { size = { 10, 1, 10 } },
		conveyor = { size = { 26, 1, 6 } },
		dropper = { size = { 4, 1, 4 } },
		collector = { size = { 6, 1, 6 } },
	}
	t:eq("a belt longer than its platform sets the footprint", Plots.footprint(wideBelt :: any), 36)

	local spacing = Plots.spacing(world)
	t:check("spacing leaves a gap between bases", spacing > Plots.footprint(world))

	t:eq("a single plot sits on the spawn line", Plots.offset(1, 1, spacing), 0)

	local count = 6
	local previous = nil
	local outermost = 0
	for index = 1, count do
		local offset = Plots.offset(index, count, spacing)
		if previous then
			-- The one failure that matters: two players standing inside each other's base
			t:check(
				("plot %d clears plot %d"):format(index, index - 1),
				offset - previous >= Plots.footprint(world),
				("gap %.1f"):format(offset - previous)
			)
		end
		previous = offset
		outermost = math.max(outermost, math.abs(offset))
	end

	t:eq("the row is centred", Plots.offset(1, count, spacing), -Plots.offset(count, count, spacing))
	-- The default baseplate is 512 studs across; a row that outgrows it drops players
	t:check("six plots fit on a default baseplate", outermost + Plots.footprint(world) / 2 <= 256)
end

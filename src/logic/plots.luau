--!strict
-- Where one player's base stands so it does not touch the next player's. Pure arithmetic,
-- kept out of the Roblox layer because overlapping plots are invisible in code and obvious
-- only once two people are standing in each other's dropper.

local Types = require("./types")

local PLOT_MARGIN = 12 -- studs of gap between neighbouring bases

local Plots = {}

-- A base sticks out past its platform: the dropper and the collector stand at the ends of
-- the belt, outside it. Spacing by the platform alone would interleave neighbours.
function Plots.footprint(world: Types.WorldDef): number
	return math.max(
		world.platform.size[1],
		world.conveyor.size[1] + world.dropper.size[1] + world.collector.size[1]
	)
end

function Plots.spacing(world: Types.WorldDef): number
	return Plots.footprint(world) + PLOT_MARGIN
end

-- Offset of plot `index` along the row, centred on zero so a server of any size stays
-- built around its spawn instead of growing off to one side.
function Plots.offset(index: number, count: number, spacing: number): number
	return (index - (count + 1) / 2) * spacing
end

return Plots

--!strict
-- A row of bases, one handed to each player who joins and taken back when they leave.
-- Every base is built up front and stands empty until claimed: a plot that materialises
-- on join makes the server hitch exactly when a player is looking at it, and an empty row
-- tells a newcomer how many people the place holds.

local Base = require("./base")
local PlotLayout = require("../logic/plots")
local Flow = require("../logic/flow")
local Types = require("../logic/types")

type ProfileData = Types.ProfileData

export type Spec = {
	world: Types.WorldDef,
	zones: { Types.ZoneDef },
	count: number,
	origin: CFrame, -- centre of the row; plots spread along its local X
	parent: Instance,
	vacantSign: string,
	nameOf: (userId: number) -> string,
}

export type Plots = {
	claim: (self: Plots, userId: number) -> (),
	release: (self: Plots, userId: number) -> (),
	sync: (self: Plots, userId: number, profile: ProfileData) -> (),
}

type Plot = {
	base: Base.Base,
	owner: number?,
	profile: ProfileData?,
	streams: Base.ZoneBoard?,
}

local Plots = {}

function Plots.new(spec: Spec): Plots
	local plots: { Plot } = {}
	local spacing = PlotLayout.spacing(spec.world)

	for index = 1, spec.count do
		local origin = spec.origin * CFrame.new(PlotLayout.offset(index, spec.count, spacing), 0, 0)
		local base = Base.build({
			world = spec.world,
			signText = spec.vacantSign,
			origin = origin,
			parent = spec.parent,
		})
		base.model.Name = ("Plot%d"):format(index)
		table.insert(plots, { base = base })
	end

	local function plotOf(userId: number): Plot?
		for _, plot in plots do
			if plot.owner == userId then
				return plot
			end
		end
		return nil
	end

	local api = {}

	function api:claim(userId: number)
		if plotOf(userId) then
			return
		end
		for _, plot in plots do
			if plot.owner == nil then
				plot.owner = userId
				plot.base.sign.Text = spec.nameOf(userId)
				plot.streams = Base.streams(plot.base, {
					zones = spec.zones,
					world = spec.world,
					drop = spec.world.drop,
					-- Read through the plot, not captured from the profile of the moment:
					-- the profile object is replaced on every purchase.
					levelOf = function()
						local profile = plot.profile
						return if profile then Flow.level(profile) else 0
					end,
					ownedOf = function()
						local profile = plot.profile
						return if profile then profile.zones else {}
					end,
				})
				return
			end
		end
		-- More players than plots is a config mistake, not a player's problem: they keep
		-- playing with a working HUD and no base of their own.
		warn(`[plots] no free plot for {userId}; row holds {spec.count}`)
	end

	function api:release(userId: number)
		local plot = plotOf(userId)
		if plot == nil then
			return
		end
		local streams = plot.streams
		if streams then
			streams:stop()
		end
		plot.streams = nil
		plot.profile = nil
		plot.owner = nil
		plot.base.sign.Text = spec.vacantSign
	end

	function api:sync(userId: number, profile: ProfileData)
		local plot = plotOf(userId)
		if plot == nil then
			return
		end
		plot.profile = profile
		local streams = plot.streams
		if streams then
			streams:refresh()
		end
	end

	return (api :: any) :: Plots
end

return Plots

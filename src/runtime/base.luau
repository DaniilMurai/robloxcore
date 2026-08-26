--!strict
-- The base is built by code, not by default.project.json: S-02 rules out carrying meshes
-- and unions through an auto-publish, and only a built base can be handed out per player
-- when plots arrive. Shapes and colours come from the title's config; the layout — what
-- stands where — is the same for every tycoon and lives here.

local TweenService = game:GetService("TweenService")

local World = require("../adapters/world")
local Types = require("../logic/types")
local Flow = require("../logic/flow")

type WorldDef = Types.WorldDef

-- Belt speed, not travel time: a longer belt then takes longer to cross instead of the
-- objects silently speeding up.
local BELT_STUDS_PER_SECOND = 8

export type Spec = {
	world: WorldDef,
	signText: string,
	-- Ground point the base is planted on: the platform sits on top of it, nothing below.
	origin: CFrame,
	parent: Instance,
}

export type Base = {
	model: Model,
	origin: CFrame,
	deckHeight: number, -- walking surface above the origin
	beltY: number, -- local height an object travels at
	beltDepth: number,
	platform: BasePart,
	conveyor: BasePart,
	dropper: BasePart,
	collector: BasePart,
	-- Where an object appears and where it stops being one. World space, so the mover
	-- never has to know the base's layout.
	dropOrigin: CFrame,
	dropTarget: CFrame,
	sign: TextLabel, -- the collector's face; a plot renames it when someone claims it
	destroy: (self: Base) -> (),
}

export type FlowSpec = {
	style: Types.PartStyle, -- config world.drop; its colour is what level 0 looks like
	levelOf: () -> number,
	origin: CFrame?, -- defaults to the base's own dropper; a zone feeds the same belt
	lane: number?, -- z offset across the belt, so streams do not share one line
}

export type ZoneSpec = {
	zones: { Types.ZoneDef },
	world: WorldDef,
	drop: Types.PartStyle,
	ownedOf: () -> { [string]: true },
	levelOf: () -> number,
}

export type ZoneBoard = {
	stop: (self: ZoneBoard) -> (),
	-- Called when the owner's profile changes. Pushed rather than polled: a poll would
	-- have to be slow enough not to burn a server and fast enough to open a zone the
	-- moment it is paid for, and there is no such period.
	refresh: (self: ZoneBoard) -> (),
}

export type BaseFlow = {
	stop: (self: BaseFlow) -> (),
}

local Base = {}

local SIGN_PIXELS_PER_STUD = 50
local BELT_CLEARANCE = 1.5 -- studs between the belt surface and an object's centre

function Base.build(spec: Spec): Base
	local world = spec.world
	local platformHeight = world.platform.size[2]
	local beltLength, beltHeight, beltDepth =
		world.conveyor.size[1], world.conveyor.size[2], world.conveyor.size[3]
	local dropperWidth, dropperHeight = world.dropper.size[1], world.dropper.size[2]
	local collectorWidth, collectorHeight = world.collector.size[1], world.collector.size[2]

	local model = Instance.new("Model")
	model.Name = "Base"

	local deck = platformHeight -- height of the walking surface above the origin
	local belt = deck + beltHeight -- height of the belt surface

	-- Read from the front, where the sign faces and the player stands: the base's local
	-- +X is the viewer's left. So the dropper sits at +X and the collector at -X, and the
	-- flow crosses the belt left to right the way a viewer expects.
	local platform = World.fromStyle(world.platform, spec.origin * CFrame.new(0, deck / 2, 0), model)
	local conveyor =
		World.fromStyle(world.conveyor, spec.origin * CFrame.new(0, deck + beltHeight / 2, 0), model)
	local dropper = World.fromStyle(
		world.dropper,
		spec.origin * CFrame.new((beltLength + dropperWidth) / 2, deck + dropperHeight / 2, 0),
		model
	)
	local collector = World.fromStyle(
		world.collector,
		spec.origin * CFrame.new(-(beltLength + collectorWidth) / 2, deck + collectorHeight / 2, 0),
		model
	)

	local surface = World.sign(
		spec.signText,
		Vector2.new(collectorWidth * SIGN_PIXELS_PER_STUD, collectorHeight * SIGN_PIXELS_PER_STUD),
		collector
	)

	model.PrimaryPart = platform
	model.Parent = spec.parent

	local base: Base = {
		model = model,
		origin = spec.origin,
		deckHeight = deck,
		beltY = belt + BELT_CLEARANCE,
		beltDepth = beltDepth,
		platform = platform,
		conveyor = conveyor,
		dropper = dropper,
		collector = collector,
		dropOrigin = spec.origin * CFrame.new(beltLength / 2 - 1, belt + BELT_CLEARANCE, 0),
		dropTarget = spec.origin * CFrame.new(-beltLength / 2, belt + BELT_CLEARANCE, 0),
		sign = surface:FindFirstChildOfClass("TextLabel") :: TextLabel,
		destroy = function(self: Base)
			self.model:Destroy()
		end,
	}
	return base
end

-- Objects on the belt are a picture of income, never its source: they carry no money, and
-- a dropped one going missing costs the player nothing.
function Base.flow(base: Base, spec: FlowSpec): BaseFlow
	local drops = Instance.new("Folder")
	drops.Name = "Drops"
	drops.Parent = base.model

	local lane = spec.lane or 0
	local origin = (spec.origin or base.dropOrigin) * CFrame.new(0, 0, lane)
	local travelSeconds = (base.dropTarget.Position - origin.Position).Magnitude / BELT_STUDS_PER_SECOND
	local floor = Flow.minInterval(spec.style.size[1], BELT_STUDS_PER_SECOND)
	local liveCap = Flow.liveCap(travelSeconds, floor)
	local running = true

	task.spawn(function()
		while running do
			local level = spec.levelOf()
			task.wait(Flow.interval(level, floor))
			if not running then
				break
			end
			-- Nothing queues up behind the cap: a skipped drop is a drop that never was.
			if #drops:GetChildren() < liveCap then
				local part = World.fromStyle({
					size = spec.style.size,
					color = Flow.tint(spec.style.color, level),
					material = spec.style.material,
				}, origin, drops)
				-- A player standing on the belt must not be shoved off it by the scenery.
				part.CanCollide = false
				local tween = TweenService:Create(
					part,
					TweenInfo.new(travelSeconds, Enum.EasingStyle.Linear),
					{ CFrame = base.dropTarget }
				)
				tween.Completed:Connect(function()
					part:Destroy()
				end)
				tween:Play()
			end
		end
	end)

	local flow: BaseFlow = {
		stop = function(_self: BaseFlow)
			running = false
			drops:Destroy()
		end,
	}
	return flow
end

-- The base's own dropper takes the first lane, every zone one of the rest.
local function laneCountOf(zones: { Types.ZoneDef }): number
	return 1 + #zones
end

local LOCKED_TRANSPARENCY = 0.65
local ZONE_PAD_MARGIN = 3 -- studs of pad around the dropper's footprint
local ZONE_PAD_THICKNESS = 0.4
local ZONE_SIGN_BAND = 0.5 -- top half of the dropper's face: the belt covers the bottom

-- Zones are built shut and opened in place, never built on purchase: a zone that appears
-- out of nothing gives the player no reason to save up for it.
function Base.zones(base: Base, spec: ZoneSpec): ZoneBoard
	local folder = Instance.new("Folder")
	folder.Name = "Zones"
	folder.Parent = base.model

	local dropperStyle = spec.world.dropper
	local dropperWidth, dropperHeight, dropperDepth =
		dropperStyle.size[1], dropperStyle.size[2], dropperStyle.size[3]

	local built: {
		[string]: {
			parts: { BasePart },
			sign: TextLabel,
			flow: BaseFlow?,
			def: Types.ZoneDef,
			lane: number,
			shown: boolean?, -- what the parts currently show, so refresh can skip no-ops
		},
	} =
		{}

	for index, zone in spec.zones do
		local at = base.origin
			* CFrame.new(zone.position[1], base.deckHeight + zone.position[2], zone.position[3])

		local pad = World.fromStyle({
			size = {
				dropperWidth + ZONE_PAD_MARGIN,
				ZONE_PAD_THICKNESS,
				dropperDepth + ZONE_PAD_MARGIN,
			},
			color = spec.world.platform.color,
			material = spec.world.platform.material,
		}, at * CFrame.new(0, ZONE_PAD_THICKNESS / 2, 0), folder)
		pad.Name = `{zone.id}_pad`

		local dropper = World.fromStyle(
			dropperStyle,
			at * CFrame.new(0, ZONE_PAD_THICKNESS + dropperHeight / 2, 0),
			folder
		)
		dropper.Name = zone.id

		local surface = World.sign(
			zone.name,
			Vector2.new(dropperWidth * SIGN_PIXELS_PER_STUD, dropperHeight * SIGN_PIXELS_PER_STUD),
			dropper,
			ZONE_SIGN_BAND
		)
		built[zone.id] = {
			parts = { pad, dropper },
			sign = surface:FindFirstChildOfClass("TextLabel") :: TextLabel,
			def = zone,
			lane = Flow.lane(index + 1, laneCountOf(spec.zones), base.beltDepth, spec.drop.size[3]),
		}
	end

	local function apply(owned: { [string]: true })
		for zoneId, entry in built do
			local isOwned = owned[zoneId] == true
			-- Refresh runs on every profile change, which includes the once-a-second income
			-- tick. Repainting unchanged parts sixty times a minute per plot is work nobody
			-- can see, so a zone is dressed once per state change.
			if entry.shown == isOwned then
				continue
			end
			entry.shown = isOwned
			for _, part in entry.parts do
				part.Transparency = if isOwned then 0 else LOCKED_TRANSPARENCY
				part.CanCollide = isOwned
			end
			entry.sign.Text = if isOwned then entry.def.name else `{entry.def.name}\n{entry.def.cost}`
			if isOwned and entry.flow == nil then
				entry.flow = Base.flow(base, {
					style = spec.drop,
					levelOf = spec.levelOf,
					-- The dropper may stand off to the side, but what it drops has to land on
					-- the belt, so the stream always starts over the belt's centre line.
					origin = base.origin * CFrame.new(entry.def.position[1], base.beltY, 0),
					lane = entry.lane,
				})
			end
		end
	end

	apply(spec.ownedOf())

	local board: ZoneBoard = {
		refresh = function(_self: ZoneBoard)
			apply(spec.ownedOf())
		end,
		stop = function(_self: ZoneBoard)
			for _, entry in built do
				if entry.flow then
					entry.flow:stop()
				end
			end
			folder:Destroy()
		end,
	}
	return board
end

-- What a title starts: the base's own stream plus every zone, sharing one lane allocator.
-- Called separately, the two would both take the centre lane and pile into each other.
function Base.streams(base: Base, spec: ZoneSpec): ZoneBoard
	local own = Base.flow(base, {
		style = spec.drop,
		levelOf = spec.levelOf,
		lane = Flow.lane(1, laneCountOf(spec.zones), base.beltDepth, spec.drop.size[3]),
	})
	local board = Base.zones(base, spec)
	local streams: ZoneBoard = {
		refresh = function(_self: ZoneBoard)
			board:refresh()
		end,
		stop = function(_self: ZoneBoard)
			own:stop()
			board:stop()
		end,
	}
	return streams
end

return Base

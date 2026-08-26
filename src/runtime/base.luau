--!strict
-- The base is built by code, not by default.project.json: S-02 rules out carrying meshes
-- and unions through an auto-publish, and only a built base can be handed out per player
-- when plots arrive. Shapes and colours come from the title's config; the layout — what
-- stands where — is the same for every tycoon and lives here.

local World = require("../adapters/world")
local Types = require("../logic/types")

type WorldDef = Types.WorldDef

export type Spec = {
	world: WorldDef,
	signText: string,
	-- Ground point the base is planted on: the platform sits on top of it, nothing below.
	origin: CFrame,
	parent: Instance,
}

export type Base = {
	model: Model,
	platform: BasePart,
	conveyor: BasePart,
	dropper: BasePart,
	collector: BasePart,
	-- Where an object appears and where it stops being one. World space, so the mover
	-- never has to know the base's layout.
	dropOrigin: CFrame,
	dropTarget: CFrame,
	destroy: (self: Base) -> (),
}

local Base = {}

local SIGN_PIXELS_PER_STUD = 50
local BELT_CLEARANCE = 1.5 -- studs between the belt surface and an object's centre

function Base.build(spec: Spec): Base
	local world = spec.world
	local platformHeight = world.platform.size[2]
	local beltLength, beltHeight = world.conveyor.size[1], world.conveyor.size[2]
	local dropperWidth, dropperHeight = world.dropper.size[1], world.dropper.size[2]
	local collectorWidth, collectorHeight = world.collector.size[1], world.collector.size[2]

	local model = Instance.new("Model")
	model.Name = "Base"

	local deck = platformHeight -- height of the walking surface above the origin
	local belt = deck + beltHeight -- height of the belt surface

	local platform = World.fromStyle(world.platform, spec.origin * CFrame.new(0, deck / 2, 0), model)
	local conveyor =
		World.fromStyle(world.conveyor, spec.origin * CFrame.new(0, deck + beltHeight / 2, 0), model)
	local dropper = World.fromStyle(
		world.dropper,
		spec.origin * CFrame.new(-(beltLength + dropperWidth) / 2, deck + dropperHeight / 2, 0),
		model
	)
	local collector = World.fromStyle(
		world.collector,
		spec.origin * CFrame.new((beltLength + collectorWidth) / 2, deck + collectorHeight / 2, 0),
		model
	)

	World.sign(
		spec.signText,
		Vector2.new(collectorWidth * SIGN_PIXELS_PER_STUD, collectorHeight * SIGN_PIXELS_PER_STUD),
		collector
	)

	model.PrimaryPart = platform
	model.Parent = spec.parent

	local base: Base = {
		model = model,
		platform = platform,
		conveyor = conveyor,
		dropper = dropper,
		collector = collector,
		dropOrigin = spec.origin * CFrame.new(-beltLength / 2 + 1, belt + BELT_CLEARANCE, 0),
		dropTarget = spec.origin * CFrame.new(beltLength / 2, belt + BELT_CLEARANCE, 0),
		destroy = function(self: Base)
			self.model:Destroy()
		end,
	}
	return base
end

return Base

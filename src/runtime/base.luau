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

export type FlowSpec = {
	style: Types.PartStyle, -- config world.drop; its colour is what level 0 looks like
	levelOf: () -> number,
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
	local beltLength, beltHeight = world.conveyor.size[1], world.conveyor.size[2]
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
		dropOrigin = spec.origin * CFrame.new(beltLength / 2 - 1, belt + BELT_CLEARANCE, 0),
		dropTarget = spec.origin * CFrame.new(-beltLength / 2, belt + BELT_CLEARANCE, 0),
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

	local travelSeconds = (base.dropTarget.Position - base.dropOrigin.Position).Magnitude
		/ BELT_STUDS_PER_SECOND
	local liveCap = Flow.liveCap(travelSeconds)
	local running = true

	task.spawn(function()
		while running do
			local level = spec.levelOf()
			task.wait(Flow.interval(level))
			if not running then
				break
			end
			-- Nothing queues up behind the cap: a skipped drop is a drop that never was.
			if #drops:GetChildren() < liveCap then
				local part = World.fromStyle({
					size = spec.style.size,
					color = Flow.tint(spec.style.color, level),
					material = spec.style.material,
				}, base.dropOrigin, drops)
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

return Base

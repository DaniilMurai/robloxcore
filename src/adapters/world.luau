--!strict
-- Procedural geometry within the publishing limits from S-02: Open Cloud does not carry
-- EditableMesh, EditableImage, PartOperation or SurfaceAppearance across an auto-publish,
-- so worlds are built from primitives, colours, materials and SurfaceGui only.

local Types = require("../logic/types")

type PartStyle = Types.PartStyle

export type PartSpec = {
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance?,
}

local World = {}

function World.part(spec: PartSpec): BasePart
	local part = Instance.new("Part")
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color
	part.Material = spec.material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = spec.parent or workspace
	return part
end

-- Config spells materials as names. A typo has to die here, at boot, naming the field,
-- rather than as a nil assignment that leaves the part plastic and silent.
function World.material(name: string): Enum.Material
	for _, item in Enum.Material:GetEnumItems() do
		if item.Name == name then
			return item
		end
	end
	error(`unknown material "{name}"`, 2)
end

function World.fromStyle(style: PartStyle, cframe: CFrame, parent: Instance?): BasePart
	return World.part({
		size = Vector3.new(style.size[1], style.size[2], style.size[3]),
		cframe = cframe,
		color = Color3.new(style.color[1], style.color[2], style.color[3]),
		material = World.material(style.material),
		parent = parent,
	})
end

-- Text on a face, not a decal: an uploaded image would need a moderated asset id, and a
-- SurfaceGui survives the auto-publish untouched.
-- `band` keeps the text in the top fraction of the face: a sign low on a small part is
-- hidden by whatever stands in front of it, and on a belt that is a moving wall of objects.
function World.sign(text: string, size: Vector2, parent: BasePart, band: number?): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(size.X, size.Y)
	surface.PixelsPerStud = 50

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, band or 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = surface

	surface.Parent = parent
	return surface
end

return World

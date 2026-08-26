--!strict
-- Procedural geometry within the publishing limits from S-02: Open Cloud does not carry
-- EditableMesh, EditableImage, PartOperation or SurfaceAppearance across an auto-publish,
-- so worlds are built from primitives, colours, materials and SurfaceGui only.

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

-- Text on a face, not a decal: an uploaded image would need a moderated asset id, and a
-- SurfaceGui survives the auto-publish untouched.
function World.sign(text: string, size: Vector2, parent: BasePart): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(size.X, size.Y)
	surface.PixelsPerStud = 50

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
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

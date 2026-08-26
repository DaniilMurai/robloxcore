--!strict
-- Lazy on purpose: a Lune test pulls src/logic without dragging in the adapter layer,
-- which only loads inside Roblox.
return setmetatable({}, {
	__index = function(_, layer: string)
		local child = script:FindFirstChild(layer)
		if not child then
			error(("robloxcore has no layer %q"):format(layer), 2)
		end
		return require(child)
	end,
})

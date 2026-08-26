--!strict
-- Player lifecycle, clock and repeating work as plain dependencies, so runtime/server.luau
-- stays free of Roblox globals and can be started against fakes in Lune.

local Players = game:GetService("Players")

local Host = {}
Host.__index = Host

function Host.new()
	return setmetatable({}, Host)
end

function Host:onJoin(handler: (userId: number) -> ())
	Players.PlayerAdded:Connect(function(player)
		handler(player.UserId)
	end)
	-- Players can already be in the game when the script starts, most visibly in Studio.
	for _, player in Players:GetPlayers() do
		task.spawn(handler, player.UserId)
	end
end

function Host:onLeave(handler: (userId: number) -> ())
	Players.PlayerRemoving:Connect(function(player)
		handler(player.UserId)
	end)
end

-- Best-effort only: BindToClose does not run when a server crashes (S-03), which is why
-- the data adapter also autosaves.
function Host:onClose(handler: () -> ())
	game:BindToClose(handler)
end

function Host:kick(userId: number, message: string)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(message)
	end
end

function Host:playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

function Host:every(seconds: number, handler: () -> ())
	task.spawn(function()
		while true do
			task.wait(seconds)
			-- One failing tick must not kill the loop for the rest of the server's life.
			local ok, err = pcall(handler)
			if not ok then
				warn(`[runtime] tick failed: {err}`)
			end
		end
	end)
end

function Host:clock(): number
	return os.time()
end

return Host

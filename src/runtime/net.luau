--!strict
-- One RemoteEvent for state and one RemoteFunction for actions, per the contract. The
-- client sends intent only: every amount is recomputed server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require("../logic/types")
local Result = require("../logic/result")

type StateSnapshot = Types.StateSnapshot
type Action = Types.Action
type Result<T> = Result.Result<T>

local Net = {}
Net.__index = Net

function Net.new()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	local state = folder:FindFirstChild("State") :: RemoteEvent?
	if state == nil then
		state = Instance.new("RemoteEvent")
		state.Name = "State"
		state.Parent = folder
	end

	local action = folder:FindFirstChild("Action") :: RemoteFunction?
	if action == nil then
		action = Instance.new("RemoteFunction")
		action.Name = "Action"
		action.Parent = folder
	end

	return setmetatable({ _state = state, _action = action }, Net)
end

function Net:sendState(userId: number, snapshot: StateSnapshot)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self._state:FireClient(player, snapshot)
	end
end

function Net:onAction(handler: (userId: number, action: Action) -> Result<StateSnapshot>)
	self._action.OnServerInvoke = function(player: Player, action: any)
		-- A malformed action is a tampered client, not a bug: answer with a Result and
		-- let the handler decide, never throw across the remote boundary.
		if type(action) ~= "table" then
			return Result.err("ProfileNotLoaded", "malformed action")
		end
		return handler(player.UserId, action)
	end
end

return Net

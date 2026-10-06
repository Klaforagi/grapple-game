-- Creator Hub's delayed-restart JSON is exposed here as the attributes dictionary.
local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))

local currentNotice

local function send(player)
	if currentNotice then Remotes.ServerRestartNotice:FireClient(player, currentNotice.message, currentNotice.restartTime) end
end

Players.PlayerAdded:Connect(send)

game.ServerRestartScheduled:Connect(function(restartTime, _, attributes)
	local message = attributes and attributes.message
	if typeof(message) ~= "string" or message == "" then return end
	message = string.sub(message, 1, 300)
	currentNotice = {message = message, restartTime = restartTime.UnixTimestamp}
	Remotes.ServerRestartNotice:FireAllClients(currentNotice.message, currentNotice.restartTime)
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))

local player = Players.LocalPlayer
local lastSent = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastSent < 0.1 then return end
	local camera = workspace.CurrentCamera
	if not camera or not player.Character then return end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then return end
	lastSent = now
	Remotes.SoccerAim:FireServer(flat.Unit)
end)

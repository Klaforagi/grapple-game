-- Optional HUD buttons only. Roblox's visible hotbar owns all number keys,
-- including during ragdoll, so a key cannot also send a second equip request.
local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local M = {}

function M.Select(toolName)
	if toolName ~= Config.toolName and toolName ~= Config.bombToolName and toolName ~= Config.pushToolName then return end
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0
		or humanoid:GetAttribute("Ragdolled") ~= true
		or humanoid:GetAttribute("GrapplePhysicsLocked") == true
		or humanoid:GetAttribute("GrappleLocalPhysicsLock") == true then return end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = character:FindFirstChild(toolName) or (backpack and backpack:FindFirstChild(toolName))
	if not tool or not tool:IsA("Tool") then return end
	-- Explicit state is idempotent if the tool has already moved on the server.
	Remotes.EquipRagdollTool:FireServer(toolName, tool.Parent ~= character)
end

return M

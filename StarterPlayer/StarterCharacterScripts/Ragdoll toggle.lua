-- Get the local player (the player running this client)
local plr = game.Players.LocalPlayer

-- Services used by this script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
-- References to shared folders and assets
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Load grapple configuration (used for debug mode, settings, etc.)
local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

local debounce = false -- cooldown

UIS.InputBegan:Connect(function(input,gpe)
	if debounce == true then return end
	if gpe then return end --If typing or on another roblox menu it won't work
	if input.KeyCode == config.ragdollKeybind then
		debounce = true
		Remotes.ToggleRagdoll:FireServer()
		
		task.delay(config.ragdollToggle_Cooldown,function()
			debounce = false
		end)
	end
end)
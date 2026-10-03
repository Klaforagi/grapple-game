-- Starts the maintained grapple UI controllers for every copy of the player's
-- Grapple Gun GUI. This replaces the old LocalScript embedded in the Length UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LengthenClient = require(ReplicatedStorage.Modules:WaitForChild("LengthenClient"))

local function initializeGrappleGui(grappleGui: Instance)
	local lengthGui = grappleGui:FindFirstChild("Length", true)
	if lengthGui then
		LengthenClient.Init(lengthGui)
		return
	end

	-- The ScreenGui can replicate before its descendants. Wait for the actual
	-- Length frame rather than silently leaving Q/E without a controller.
	task.spawn(function()
		local found = grappleGui:WaitForChild("Length", 10)
		if found then LengthenClient.Init(found) end
	end)
end

local function watchGrappleGui(instance: Instance)
	if instance.Name ~= "Grapple Gun" then return end
	initializeGrappleGui(instance)
	instance.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "Length" then
			LengthenClient.Init(descendant)
		end
	end)
end

for _, child in ipairs(playerGui:GetChildren()) do
	watchGrappleGui(child)
end
playerGui.ChildAdded:Connect(watchGrappleGui)

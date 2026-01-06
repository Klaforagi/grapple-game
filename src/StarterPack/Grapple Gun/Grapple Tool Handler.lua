-- LocalScript (client)
-- This script handles the CLIENT-SIDE behavior of the grapple tool.
-- Responsibilities:
-- • Detect when the tool is equipped / unequipped
-- • Fire the grapple request to the server when clicked
-- • Change the mouse cursor icon based on grapple state
-- • Prevent tool duplication issues while grappling

----------------------------------------------------------------
-- PLAYER & TOOL REFERENCES
----------------------------------------------------------------

-- Reference to the local player
local plr = game.Players.LocalPlayer

-- The tool this script is inside of
local tool = script.Parent

----------------------------------------------------------------
-- SERVICES & INPUT
----------------------------------------------------------------

-- ReplicatedStorage holds shared modules and remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Mouse used for aiming the grapple
local mouse = plr:GetMouse()

-- Camera used to convert screen position into a world ray
local camera = game.Workspace.CurrentCamera

local UserInputService = game:GetService("UserInputService")


----------------------------------------------------------------
-- MODULES & CONFIG
----------------------------------------------------------------

-- RemoteEvents used to communicate with the server
local Remotes = ReplicatedStorage.Remotes

-- Grapple configuration (icons, tool name, settings)
local GrappleProperties = require(ReplicatedStorage.GrappleConfig)

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

-- Tracks whether the tool is currently equipped
local equipped = false

----------------------------------------------------------------
-- CURSOR ICON HANDLER
----------------------------------------------------------------

-- Updates the mouse cursor icon depending on the grapple state
local updateCursorIcon = function(enable)

	-- If custom cursors are disabled in config, do nothing
	if not GrappleProperties.CustomCursorsEnabled then return end

	if enable then
		-- Only change cursor if tool is equipped
		if equipped then
			-- If grapple is actively attached
			if tool:GetAttribute("HasGrappled") then
				mouse.Icon = GrappleProperties.GrappleInUseIcon

				-- If grapple is not attached
			else
				-- Show cooldown / blocked cursor
				if tool:GetAttribute("InCooldown") then
					mouse.Icon = GrappleProperties.MouseObstructedIcon
				else
					-- Ready-to-fire cursor
					mouse.Icon = GrappleProperties.CustomCursorIcon
				end
			end
		end
	else
		-- Reset cursor when tool is unequipped
		mouse.Icon = ""
	end
end

----------------------------------------------------------------
-- TOOL EQUIP / UNEQUIP
----------------------------------------------------------------

-- Runs when the tool is equipped
tool.Equipped:Connect(function()
	equipped = true
	updateCursorIcon(true)
end)

-- Runs when the tool is unequipped
tool.Unequipped:Connect(function()
	updateCursorIcon()
	equipped = false
end)

----------------------------------------------------------------
-- TOOL ACTIVATION (CLICK)
----------------------------------------------------------------

-- Fires when the player clicks while holding the tool
tool.Activated:Connect(function()

	-- Convert mouse position on screen into a 3D ray
	local screenRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Calculate a far hit position (used as fallback)
	local hitPos = screenRay.Origin + screenRay.Direction * 1000

	-- Send grapple request to the server
	-- mouse.Hit.Position = actual world hit point
	-- camera.CFrame.Position = camera origin (used for clamping distance)
	Remotes.FireGrapple:FireServer(mouse.Hit.Position, camera.CFrame.Position)
end)

----------------------------------------------------------------
-- ATTRIBUTE CHANGE LISTENERS
----------------------------------------------------------------

-- Update cursor when cooldown state changes
tool:GetAttributeChangedSignal("InCooldown"):Connect(function()
	updateCursorIcon(true)
end)

-- Update cursor when grapple starts/stops being used
tool:GetAttributeChangedSignal("InUse"):Connect(function()
	updateCursorIcon(not plr.Backpack:FindFirstChild(GrappleProperties.toolName))
end)

-- Update cursor when grapple successfully attaches
tool:GetAttributeChangedSignal("HasGrappled"):Connect(function()
	updateCursorIcon(not plr.Backpack:FindFirstChild(GrappleProperties.toolName))
end)

----------------------------------------------------------------
-- BACKPACK SAFETY HANDLING
----------------------------------------------------------------

-- Prevents the grapple tool from being duplicated or lost
-- while it is actively grappling
plr.Backpack.ChildAdded:Connect(function(child)
	if child.Name == GrappleProperties.toolName then
		-- If grapple is currently active, force it back to character
		if tool:GetAttribute("InUse") or tool:GetAttribute("HasGrappled") then
			child.Parent = plr.Character
		end
	end
end)

local char = plr.Character or plr.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")

char.ChildAdded:Connect(function(child)
	if child.Name == GrappleProperties.toolName then
		-- If player is currently ragdolled, force it back to the inventory
		if hum:HasTag("Ragdoll") then
			child.Parent = plr.Backpack
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if not equipped then return end

	if input.KeyCode == GrappleProperties.toggleWallMode then
		Remotes.ToggleWallMode:FireServer()
	end
end)

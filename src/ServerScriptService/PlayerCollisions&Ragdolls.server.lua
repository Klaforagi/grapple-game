-- This script runs on the SERVER
-- Purpose:
-- 1) Prevent players from colliding with each other
-- 2) Set up ragdoll-related tags and networking
-- 3) Ensure player characters are properly configured when they spawn

-- Force this script to live in ServerScriptService
-- (Prevents it from accidentally being placed somewhere else)
script.Parent = game:GetService("ServerScriptService")

----------------------------------------------------------------
-- COLLISION GROUP SETUP
----------------------------------------------------------------

-- PhysicsService allows us to control collision rules
local PhysService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

-- Register a collision group named "p" (used for players)
-- If it already exists, Roblox will simply return it
local PlayerGroup = PhysService:RegisterCollisionGroup("p")

-- Make players NOT collide with other players
-- "p" vs "p" collision is disabled
PhysService:CollisionGroupSetCollidable("p", "p", false)

----------------------------------------------------------------
-- RAGDOLL SERVICE
----------------------------------------------------------------

-- Load the ragdoll service module
-- This handles converting characters into ragdoll physics
local ragdollService = require(game.ReplicatedStorage.Modules.RagdollService)

----------------------------------------------------------------
-- NO COLLISION FUNCTION
----------------------------------------------------------------

-- Assigns all BaseParts in a character to the player collision group
-- This ensures player parts do not collide with other players
function NoCollide(model)
	for k, v in pairs(model:GetChildren()) do
		if v:IsA("BasePart") then
			-- Move the part into the "p" collision group
			v.CollisionGroup = "p"
		end
	end
end

----------------------------------------------------------------
-- PLAYER JOIN & CHARACTER SPAWN
----------------------------------------------------------------

-- Runs when a player joins the game
game:GetService("Players").PlayerAdded:Connect(function(player)

	-- Runs every time the player's character spawns
	player.CharacterAdded:Connect(function(char)

		-- Wait for important character parts to exist
		char:WaitForChild("HumanoidRootPart")
		char:WaitForChild("Head")
		char:WaitForChild("Humanoid")

		-- Small delay to ensure all parts are fully created
		wait(0.1)

		-- Apply no-collision to the character
		NoCollide(char)

		-- Safety check: re-apply collision settings if character exists
		if player.Character then
			NoCollide(player.Character)
		end
	end)
end)

----------------------------------------------------------------
-- ADDITIONAL SERVICES
----------------------------------------------------------------

-- ReplicatedStorage is used for shared modules and assets
local replicatedStorage = game:GetService('ReplicatedStorage')

-- ContextActionService is typically used for input handling
-- (Not directly used here, but required for consistency)
local contextActionService = game:GetService('ContextActionService')

-- Players service reference
local players = game:GetService('Players')

----------------------------------------------------------------
-- WARP NETWORK SETUP (RAGDOLL NETWORKING)
----------------------------------------------------------------

-- Load Warp networking system from ragdoll package
-- Warp is used to safely handle server-client communication
local warp = require(game.ReplicatedStorage.Modules.RagdollService.Shared.Packages.warp)

-- Create a server network for ragdoll events
-- Includes rate limiting to prevent spam/exploits
local network = warp.Server('Ragdoll', {
	rateLimit = {
		maxEntrance = 10, -- Max requests per interval
		interval = 1     -- Interval in seconds
	}
})

-- Stores debounces for ragdoll toggles (per character or player)
local ragdollDebounces = {}

----------------------------------------------------------------
-- RAGDOLL STATE COUNTER
----------------------------------------------------------------

-- Tracks how many systems currently want a character ragdolled
-- This prevents conflicts where one system disables ragdoll
-- while another still needs it enabled
local function ragdoll(character: Model, enabled: boolean)
	if not character or not character.Parent or not character:IsA('Model') then return end

	-- Increase or decrease ragdoll count safely
	character:SetAttribute(
		'RagdollCount',
		math.clamp(
			(character:GetAttribute('RagdollCount') or 0)
				+ ((enabled and 1) or -1),
			0,
			math.huge
		)
	)
end

----------------------------------------------------------------
-- ADD RAGDOLL TAGS TO PLAYERS
----------------------------------------------------------------

-- When players join, tag their humanoids so the ragdoll system
-- knows how and when to ragdoll them
players.PlayerAdded:Connect(function(player)

	player.CharacterAdded:Connect(function(character)

		-- Wait for the humanoid to exist
		local humanoid = character:WaitForChild('Humanoid') :: Humanoid

		-- Mark this humanoid as ragdoll-capable
		humanoid:AddTag('Ragdollable')

		-- Automatically ragdoll when falling
		humanoid:AddTag('RagdollOnHumanoidFall')

		-- Automatically ragdoll on death
		humanoid:AddTag('RagdollOnHumanoidDied')


	end)
end)



local Remotes = replicatedStorage.Remotes

Remotes.ToggleRagdoll.OnServerEvent:Connect(function(plr)
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hum : Humanoid = char:WaitForChild("Humanoid")

	if hum:HasTag("Ragdoll") then
		hum:RemoveTag("Ragdoll")
	else
		hum:AddTag("Ragdoll")
	end
end)

CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(instance : Instance)
	if instance:IsA("Humanoid") then
		instance:UnequipTools()
		local char = instance.Parent

		if char and char:IsA("Model") then
			for _,v in pairs(char:GetChildren()) do
				if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
					task.spawn(function()
						-- Ragdolling disables cancollide so I have to use a loop
						while CollectionService:HasTag(instance, "Ragdoll") do
							v.CanCollide = true
							task.wait(0.25)
						end
					end)
				end
			end
		end
	end
end)

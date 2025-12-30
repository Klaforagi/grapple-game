-- Visual bolts for every server-created hitbox (client)
-- This script runs on the CLIENT and is responsible for showing
-- a visible "grapple bolt" for every grapple hitbox created by the server

-- Get the local player (the player running this client)
local plr = game.Players.LocalPlayer

-- Get the character model of the player
-- If it doesn't exist yet, wait until it loads
local char = plr.Character or plr.CharacterAdded:Wait()

-- Get the HumanoidRootPart, which is the main body part used for positioning
local root : BasePart = char:WaitForChild("HumanoidRootPart")

-- Services used by this script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- References to shared folders and assets
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Templates = ReplicatedStorage:WaitForChild("Templates")

-- Template used to visually represent the grapple bolt
local BoltTemplate = Templates:FindFirstChild("Bolt")

-- Load grapple configuration (used for debug mode, settings, etc.)
local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

-- This table keeps track of which visual belongs to which hitbox
-- Format:
-- visualMap[hitbox] = {
--     visual = BasePart (the visual bolt),
--     conn = RBXScriptConnection (used to clean up safely)
-- }
local visualMap = {}

-- Debug print function
-- Only prints messages if debugMode is enabled in the config
local function dbg(...)
	if config.debugMode then
		print("[VBolt]", ...)
	end
end

-- Creates a visual bolt for a given hitbox
local function createVisualForHitbox(hitbox)
	-- Safety check: only continue if this is a valid BasePart
	if not hitbox or not hitbox:IsA("BasePart") then return end

	-- If a visual already exists for this hitbox, reuse it
	if visualMap[hitbox] and visualMap[hitbox].visual and visualMap[hitbox].visual.Parent then
		return visualMap[hitbox].visual
	end

	-- Create the visual bolt
	local vb

	-- If a Bolt template exists, clone it
	if BoltTemplate and BoltTemplate:IsA("BasePart") then
		vb = BoltTemplate:Clone()
	else
		-- Fallback: create a simple part if no template exists
		vb = Instance.new("Part")
		vb.Size = Vector3.new(0.3, 0.3, 1)
	end

	-- Set visual properties
	vb.Name = "VisualGrappleBolt"
	vb.CanCollide = false        -- Visual only, no physics
	vb.Anchored = true           -- Prevents physics movement
	vb.CastShadow = false        -- Cleaner look
	vb.Transparency = 0
	vb.Parent = workspace        -- Must be in workspace to be visible

	-- Cleanup connection reference
	local conn

	-- Detect when the hitbox is removed from the game
	conn = hitbox.AncestryChanged:Connect(function(_, parent)
		if not parent then
			-- Hitbox was removed from the workspace
			if vb and vb.Parent then vb:Destroy() end
			if conn then conn:Disconnect() end
			visualMap[hitbox] = nil
			dbg("Cleanup visual for removed hitbox")
		end
	end)

	-- Extra safety: detect when Destroy() is explicitly called
	hitbox.Destroying:Connect(function()
		if vb and vb.Parent then vb:Destroy() end
		if conn then conn:Disconnect() end
		visualMap[hitbox] = nil
		dbg("Cleanup visual on Destroy()")
	end)

	-- Store the visual and its cleanup connection
	visualMap[hitbox] = { visual = vb, conn = conn }

	dbg("Created visual bolt for hitbox:", hitbox:GetFullName())
	return vb
end

-- Manually removes a visual bolt for a hitbox
local function destroyVisualForHitbox(hitbox)
	local entry = visualMap[hitbox]
	if not entry then return end

	-- Disconnect cleanup connection
	if entry.conn then entry.conn:Disconnect() end

	-- Destroy the visual part
	if entry.visual and entry.visual.Parent then
		entry.visual:Destroy()
	end

	-- Remove from the tracking table
	visualMap[hitbox] = nil
	dbg("Manually destroyed visual for hitbox")
end

-- Listen for the server telling the client a grapple was fired
-- The server sends the hitbox that represents the grapple
Remotes:WaitForChild("FireGrapple").OnClientEvent:Connect(function(hitbox)
	if not hitbox or not hitbox:IsA("BasePart") then
		dbg("FireGrapple event received invalid hitbox:", hitbox)
		return
	end

	-- Create a visual bolt for the hitbox
	createVisualForHitbox(hitbox)
end)

-- Runs every frame (RenderStepped)
-- Keeps visuals perfectly synced to their hitboxes
RunService.RenderStepped:Connect(function(dt)
	for hitbox, entry in pairs(visualMap) do
		local vb = entry.visual

		-- If something broke or got deleted, clean it up
		if not hitbox or not vb or not vb.Parent then
			destroyVisualForHitbox(hitbox)
		else
			-- Move the visual bolt to match the hitbox exactly
			local targetCFrame = hitbox.CFrame

			-- Optional smoothing (currently disabled)
			-- vb.CFrame = vb.CFrame:Lerp(targetCFrame, math.clamp(20 * dt, 0, 1))

			vb.CFrame = targetCFrame
		end
	end
end)

-- Folder where the server places grapple hitboxes
local HitboxFolder = workspace:WaitForChild("Hitbox")

-- Detect hitboxes that are added AFTER the client loads
HitboxFolder.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		dbg("ChildAdded detected hitbox:", child.Name)
		createVisualForHitbox(child)
	end
end)

-- Detect hitboxes that already existed BEFORE the client loaded
for _, child in ipairs(HitboxFolder:GetChildren()) do
	if child:IsA("BasePart") then
		createVisualForHitbox(child)
	end
end

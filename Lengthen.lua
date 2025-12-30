-- LocalScript (client)
-- Purpose:
-- This script allows the player to SHORTEN or LENGTHEN the grapple rope
-- while grappling a player or a wall.
-- It works by changing the RopeConstraint's WinchTarget value
-- and syncing that change with the server.

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------

-- Reference to the local player
local plr = game.Players.LocalPlayer

-- Shared storage for remotes and configs
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Used to detect keyboard input
local UserInputService = game:GetService("UserInputService")

-- Used for frame-based updates
local RunService = game:GetService("RunService")

-- Used to smoothly update UI values
local TweenService = game:GetService("TweenService")

----------------------------------------------------------------
-- MODULES & CONFIG
----------------------------------------------------------------

-- RemoteEvents folder
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Grapple configuration module
local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

----------------------------------------------------------------
-- TUNING VALUES (FROM CONFIG)
----------------------------------------------------------------

-- How many studs the rope changes per step
local STEP_STUDS = config.LengthStep or 2

-- Minimum allowed rope length
local MIN_LEN = config.MinRopeLength or 0

-- Maximum allowed rope length
local MAX_LEN = config.MaxRopeLength or config.maxRopeLength or config.MaxDistance or 500


-- How often rope length updates while holding a key
local REPEAT_INTERVAL = 0.08

----------------------------------------------------------------
-- RUNTIME REFERENCES
----------------------------------------------------------------

-- Player or object currently being grappled
local currentVictim = nil

-- RopeConstraint currently being controlled
local currentRopeConstraint = nil

-- Beam visual for the rope
local currentRopeVisual = nil

----------------------------------------------------------------
-- INPUT STATE
----------------------------------------------------------------

-- Tracks whether the player is holding shorten or lengthen keys
local held = {
	shorten = false,
	lengthen = false
}

-- Used to control repeat timing
local lastTickAcc = 0

-- Connections for input and heartbeat
local inputConn = nil
local heartbeatConn = nil

----------------------------------------------------------------
-- UI TWEEN SETTINGS
----------------------------------------------------------------

local fadeInfo = TweenInfo.new(
	0.25,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

-- Fades the rope UI in or out
local function tweenVisible(visible)
	local goal = {
		ImageTransparency = visible and script.Parent.Percentage.ProgressScript.ImageTrans.Value or 1
	}

	TweenService:Create(script.Parent.Frame1.ImageLabel, fadeInfo, goal):Play()
	TweenService:Create(script.Parent.Frame2.ImageLabel, fadeInfo, goal):Play()
end

----------------------------------------------------------------
-- DEBUG HELPER
----------------------------------------------------------------

local function dbg(...)
	if config.debugMode then
		print("[RopeAdjust]", ...)
	end
end

----------------------------------------------------------------
-- ROPE LENGTH HELPERS
----------------------------------------------------------------


-- Returns the current WinchTarget length from the RopeConstraint
local function getCurrentTargetLength()
	if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
		return currentRopeConstraint.WinchTarget
	end
	return 0
end

-- Sets the WinchTarget locally (optimistic update)
-- The server will later confirm this value
local function setLocalTargetLength(newLen)
	if not currentRopeConstraint then return end
	currentRopeConstraint.WinchTarget = newLen
end

----------------------------------------------------------------
-- UI PERCENTAGE HANDLING
----------------------------------------------------------------

-- Safely updates the Percentage NumberValue used by the UI
local function safeSetPercentageFromLength(length)
	local pctObj = script.Parent:FindFirstChild("Percentage")

	-- Create Percentage value if missing
	if not pctObj or not pctObj:IsA("NumberValue") then
		pctObj = Instance.new("NumberValue")
		pctObj.Name = "Percentage"
		pctObj.Parent = script.Parent
		dbg("Created Percentage NumberValue (was missing).")
	end

	-- Convert rope length to percentage
	local pct = 0
	if MAX_LEN > 0 then
		pct = math.clamp((length / MAX_LEN) * 100, 0, 100)
	end

	-- Smoothly tween the NumberValue
	local tween = TweenService:Create(
		pctObj,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = pct }
	)

	tween:Play()
	dbg(("Set Percentage = %.2f%% (target=%.2f, max=%.2f)"):format(pct, length, MAX_LEN))
end

----------------------------------------------------------------
-- APPLY ROPE LENGTH CHANGE
----------------------------------------------------------------

-- Sends rope length change request to the server
local function applyLengthChange(newLen)
	newLen = math.clamp(newLen, MIN_LEN, MAX_LEN)

	-- Ensure remote exists
	if not Remotes:FindFirstChild("ChangeLength") then
		warn("[RopeAdjust] Remotes.ChangeLength missing")
		return
	end

	-- Tell the server to change rope length
	Remotes.ChangeLength:FireServer(newLen)
	dbg("Fired ChangeLength ->", newLen)

	-- Optimistically update locally for instant feedback
	setLocalTargetLength(newLen)

	-- Update UI percentage
	safeSetPercentageFromLength(newLen)
end

----------------------------------------------------------------
-- HOLD-TO-REPEAT LOGIC
----------------------------------------------------------------

-- Processes held inputs every REPEAT_INTERVAL seconds
local function processHeld(dt)
	lastTickAcc = lastTickAcc + dt

	while lastTickAcc >= REPEAT_INTERVAL do
		lastTickAcc = lastTickAcc - REPEAT_INTERVAL

		-- Stop if rope no longer exists
		if not currentRopeConstraint or not currentRopeConstraint:IsA("RopeConstraint") then
			break
		end

		local changed = false

		-- Base length comes from WinchTarget
		local newLen = getCurrentTargetLength()

		-- Increase rope length
		if held.lengthen then
			newLen = newLen + STEP_STUDS
			changed = true
		end

		-- Decrease rope length
		if held.shorten then
			newLen = newLen - STEP_STUDS
			changed = true
		end

		-- Optional anchoring logic (currently disabled)
		local char = plr.Character
		local torso = char and (char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso"))
		if torso then
			-- if held.shorten then torso.Anchored = true else torso.Anchored = false end
		end

		-- Apply change if needed
		if changed then
			applyLengthChange(newLen)
		end
	end
end

----------------------------------------------------------------
-- INPUT SETUP / CLEANUP
----------------------------------------------------------------

-- Disconnects all input and update connections
local function disconnectInput()
	if inputConn then inputConn:Disconnect() inputConn = nil end
	if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end

	held.shorten = false
	held.lengthen = false
	lastTickAcc = 0

	dbg("Input/heartbeat disconnected and hold state reset")
end

-- Sets up keyboard input handling for rope control
local function setupInputHandlers()
	disconnectInput()

	-- Detect key press
	inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not currentRopeConstraint or not currentRopeConstraint:IsA("RopeConstraint") then return end

		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == config.lengthenRope then
				held.lengthen = true
				dbg("Hold start: lengthen")
			elseif input.KeyCode == config.shortenRope then
				held.shorten = true
				dbg("Hold start: shorten")
			end
		end
	end)

	-- Detect key release
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == config.lengthenRope then
				held.lengthen = false
				dbg("Hold end: lengthen")
			elseif input.KeyCode == config.shortenRope then
				held.shorten = false
				dbg("Hold end: shorten")
			end
		end
	end)

	-- Run hold logic every frame
	lastTickAcc = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not currentRopeConstraint then return end
		processHeld(dt)
		updateVisualSlack()
	end)


	dbg("Input handlers set up (winch-target mode, hold-to-repeat enabled)")
end

----------------------------------------------------------------
-- GRAPPLE EVENTS (PLAYER)
----------------------------------------------------------------

Remotes:WaitForChild("GrappledPlayer").OnClientEvent:Connect(function(victim : Model, ropeConstraint : RopeConstraint, ropeVisual : Beam)
	dbg("GrappledPlayer event. Victim:", victim and victim.Name or "nil")

	currentVictim = victim
	currentRopeConstraint = ropeConstraint
	currentRopeVisual = ropeVisual

	-- Initialize UI using WinchTarget
	if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
		local initialTarget = currentRopeConstraint.WinchTarget
		safeSetPercentageFromLength(initialTarget)
	else
		dbg("No RopeConstraint provided or invalid")
	end

	-- Enable or disable input/UI
	if victim then
		setupInputHandlers()
		tweenVisible(true)
	else
		tweenVisible(false)
		disconnectInput()
		currentVictim = nil
		currentRopeConstraint = nil
		currentRopeVisual = nil
		dbg("Grapple ended; cleaned up")
	end
end)

----------------------------------------------------------------
-- GRAPPLE EVENTS (WALL)
----------------------------------------------------------------

Remotes:WaitForChild("GrappledWall").OnClientEvent:Connect(function(impactAtt : Attachment, ropeConstraint : RopeConstraint, ropeVisual : Beam)
	dbg("GrappledWall event. Impact Attachment:", impactAtt and impactAtt.Name or "nil")

	currentRopeConstraint = ropeConstraint
	currentRopeVisual = ropeVisual

	-- Initialize UI using WinchTarget
	if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
		local initialTarget = currentRopeConstraint.WinchTarget
		safeSetPercentageFromLength(initialTarget)
	else
		dbg("No RopeConstraint provided or invalid")
	end

	if impactAtt then
		setupInputHandlers()
		tweenVisible(true)
	else
		tweenVisible(false)
		disconnectInput()
		currentVictim = nil
		currentRopeConstraint = nil
		currentRopeVisual = nil
		dbg("Grapple ended; cleaned up")
	end
end)

----------------------------------------------------------------
-- FINAL CLEANUP
----------------------------------------------------------------

-- Cleanup if the script is removed
script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		disconnectInput()
	end
end)

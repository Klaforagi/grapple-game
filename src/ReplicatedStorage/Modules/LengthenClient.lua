-- ModuleScript (client): ReplicatedStorage.Modules.LengthenClient
-- Purpose:
-- Allows the player to SHORTEN or LENGTHEN the grapple rope while grappling.
-- Works by changing RopeConstraint.WinchTarget and syncing change to the server.
--
-- Call: require(...).Init(rootGui)

local M = {}

function M.Init(rootGui: Instance)
	----------------------------------------------------------------
	-- SERVICES
	----------------------------------------------------------------
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")

	local plr = Players.LocalPlayer
	if not plr then
		warn("[LengthenClient] LocalPlayer missing")
		return
	end

	if not rootGui or not rootGui:IsA("Instance") then
		warn("[LengthenClient] Init expected a UI instance, got:", rootGui)
		return
	end

	-- Prevent double-init if something re-runs the script
	if rootGui:GetAttribute("LengthenClientInit") then
		return
	end
	rootGui:SetAttribute("LengthenClientInit", true)

	----------------------------------------------------------------
	-- MODULES & CONFIG
	----------------------------------------------------------------
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

	----------------------------------------------------------------
	-- TUNING VALUES (FROM CONFIG)
	----------------------------------------------------------------
	local STEP_STUDS = config.LengthStep or 2
	local MIN_LEN = config.MinRopeLength or 0
	local MAX_LEN = config.MaxRopeLength or config.maxRopeLength or config.MaxDistance or 500
	local REPEAT_INTERVAL = 0.08

	----------------------------------------------------------------
	-- UI REFERENCES
	----------------------------------------------------------------
	-- Root gui is the parent object the old script lived under (Length)
	local percentageObj = rootGui:FindFirstChild("Percentage")
	local frame1 = rootGui:FindFirstChild("Frame1")
	local frame2 = rootGui:FindFirstChild("Frame2")

	-- Keep parity with your old code (this is weirdly nested, but we’ll respect it)
	-- Old: script.Parent.Percentage.ProgressScript.ImageTrans.Value
	local function getTargetTransparency()
		local p = rootGui:FindFirstChild("Percentage")
		if p then
			local progressScript = p:FindFirstChild("ProgressScript")
			if progressScript then
				local imageTrans = progressScript:FindFirstChild("ImageTrans")
				if imageTrans and imageTrans:IsA("NumberValue") then
					return imageTrans.Value
				end
			end
		end
		return 0 -- fallback: visible
	end

	----------------------------------------------------------------
	-- RUNTIME REFERENCES
	----------------------------------------------------------------
	local currentVictim: Model? = nil
	local currentRopeConstraint: RopeConstraint? = nil
	local currentRopeVisual: Beam? = nil

	----------------------------------------------------------------
	-- INPUT STATE
	----------------------------------------------------------------
	local held = { shorten = false, lengthen = false }
	local lastTickAcc = 0

	-- Connections
	local inputBeganConn: RBXScriptConnection? = nil
	local inputEndedConn: RBXScriptConnection? = nil
	local heartbeatConn: RBXScriptConnection? = nil

	----------------------------------------------------------------
	-- UI TWEEN SETTINGS
	----------------------------------------------------------------
	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function tweenVisible(visible: boolean)
		if not (frame1 and frame2) then return end
		local img1 = frame1:FindFirstChild("ImageLabel")
		local img2 = frame2:FindFirstChild("ImageLabel")
		if not (img1 and img2) then return end

		local goal = {
			ImageTransparency = visible and getTargetTransparency() or 1
		}

		TweenService:Create(img1, fadeInfo, goal):Play()
		TweenService:Create(img2, fadeInfo, goal):Play()
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
	local function getCurrentTargetLength(): number
		if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
			return currentRopeConstraint.WinchTarget
		end
		return 0
	end

	local function setLocalTargetLength(newLen: number)
		if not currentRopeConstraint then return end
		currentRopeConstraint.WinchTarget = newLen
	end

	----------------------------------------------------------------
	-- UI PERCENTAGE HANDLING
	----------------------------------------------------------------
	local function safeSetPercentageFromLength(length: number)
		local pctObj = rootGui:FindFirstChild("Percentage")

		if not pctObj or not pctObj:IsA("NumberValue") then
			pctObj = Instance.new("NumberValue")
			pctObj.Name = "Percentage"
			pctObj.Parent = rootGui
			dbg("Created Percentage NumberValue (was missing).")
		end

		local pct = 0
		if MAX_LEN > 0 then
			pct = math.clamp((length / MAX_LEN) * 100, 0, 100)
		end

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
	local function applyLengthChange(newLen: number)
		newLen = math.clamp(newLen, MIN_LEN, MAX_LEN)

		local changeLengthRemote = Remotes:FindFirstChild("ChangeLength")
		if not changeLengthRemote then
			warn("[RopeAdjust] Remotes.ChangeLength missing")
			return
		end

		changeLengthRemote:FireServer(newLen)
		dbg("Fired ChangeLength ->", newLen)

		setLocalTargetLength(newLen)
		safeSetPercentageFromLength(newLen)
	end

	----------------------------------------------------------------
	-- HOLD-TO-REPEAT LOGIC
	----------------------------------------------------------------
	local function processHeld(dt: number)
		lastTickAcc += dt

		while lastTickAcc >= REPEAT_INTERVAL do
			lastTickAcc -= REPEAT_INTERVAL

			if not currentRopeConstraint or not currentRopeConstraint:IsA("RopeConstraint") then
				break
			end

			local changed = false
			local newLen = getCurrentTargetLength()

			if held.lengthen then
				newLen += STEP_STUDS
				changed = true
			end

			if held.shorten then
				newLen -= STEP_STUDS
				changed = true
			end

			if changed then
				applyLengthChange(newLen)
			end
		end
	end

	----------------------------------------------------------------
	-- INPUT SETUP / CLEANUP
	----------------------------------------------------------------
	local function disconnectInput()
		if inputBeganConn then inputBeganConn:Disconnect() inputBeganConn = nil end
		if inputEndedConn then inputEndedConn:Disconnect() inputEndedConn = nil end
		if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end

		held.shorten = false
		held.lengthen = false
		lastTickAcc = 0

		dbg("Input/heartbeat disconnected and hold state reset")
	end

	local function setupInputHandlers()
		disconnectInput()

		inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
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

		-- IMPORTANT: store this connection so it can be disconnected
		inputEndedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
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

		lastTickAcc = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt)
			if not currentRopeConstraint then return end
			processHeld(dt)
		end)

		dbg("Input handlers set up (winch-target mode, hold-to-repeat enabled)")
	end

	----------------------------------------------------------------
	-- GRAPPLE EVENTS (PLAYER)
	----------------------------------------------------------------
	Remotes:WaitForChild("GrappledPlayer").OnClientEvent:Connect(function(victim: Model?, ropeConstraint: RopeConstraint?, ropeVisual: Beam?)
		dbg("GrappledPlayer event. Victim:", victim and victim.Name or "nil")

		currentVictim = victim
		currentRopeConstraint = ropeConstraint
		currentRopeVisual = ropeVisual

		if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
			safeSetPercentageFromLength(currentRopeConstraint.WinchTarget)
		else
			dbg("No RopeConstraint provided or invalid")
		end

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
	Remotes:WaitForChild("GrappledWall").OnClientEvent:Connect(function(impactAtt: Attachment?, ropeConstraint: RopeConstraint?, ropeVisual: Beam?)
		dbg("GrappledWall event. Impact Attachment:", impactAtt and impactAtt.Name or "nil")

		currentRopeConstraint = ropeConstraint
		currentRopeVisual = ropeVisual

		if currentRopeConstraint and currentRopeConstraint:IsA("RopeConstraint") then
			safeSetPercentageFromLength(currentRopeConstraint.WinchTarget)
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
	rootGui.AncestryChanged:Connect(function()
		if not rootGui:IsDescendantOf(game) then
			disconnectInput()
		end
	end)
end

return M

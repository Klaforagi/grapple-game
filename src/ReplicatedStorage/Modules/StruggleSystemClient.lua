-- ModuleScript (client): ReplicatedStorage.Modules.StruggleSystemClient
-- Reliable struggle handler using ContextActionService.
-- Call: require(...).Init(rootGui)

local M = {}

function M.Init(rootGui: Instance)
	----------------------------------------------------------------
	-- SERVICES
	----------------------------------------------------------------
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local ContextActionService = game:GetService("ContextActionService")
	local TweenService = game:GetService("TweenService")

	local plr = Players.LocalPlayer
	if not plr then
		warn("[StruggleSystemClient] LocalPlayer missing")
		return
	end

	if not rootGui then
		warn("[StruggleSystemClient] Init expected rootGui, got nil")
		return
	end

	-- Prevent double-init if the UI gets reinserted
	if rootGui:GetAttribute("StruggleSystemClientInit") then
		return
	end
	rootGui:SetAttribute("StruggleSystemClientInit", true)

	----------------------------------------------------------------
	-- MODULES & CONFIG
	----------------------------------------------------------------
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

	----------------------------------------------------------------
	-- CONFIG
	----------------------------------------------------------------
	local minStruggleValue = config.minStruggleValue or 25
	local maxStruggleValue = config.maxStruggleValue or 30
	local struggleIncrement = config.struggleIncrement or 1
	local struggleDecrease = (config.struggleDecrease ~= nil) and config.struggleDecrease or true
	local struggleDecreaseAmt = config.struggleDecreaseAmt or 1
	local struggleDecreaseInterval = config.struggleDecreaseInterval or 1

	local STRUGGLE_KEY = config.struggleKeybind or Enum.KeyCode.Space

	----------------------------------------------------------------
	-- STATE
	----------------------------------------------------------------
	local active = false
	local progressValue = 0
	local targetValue = 0
	local decreaseConn: RBXScriptConnection? = nil
	local currentStruggleRemote: RemoteEvent? = nil

	-- IMPORTANT: use a stable action name so we can always unbind even if script restarts.
	-- (Random names can make cleanup harder across reloads.)
	local KEY_ACTION_NAME = "STRUGGLE_KEY_ACTION"
	local MOUSE_ACTION_NAME = "STRUGGLE_MOUSE_ACTION"

	----------------------------------------------------------------
	-- DEBUG
	----------------------------------------------------------------
	local function dbg(...)
		if config.debugMode then
			print("[Struggle]", ...)
		end
	end

	----------------------------------------------------------------
	-- UI TWEEN
	----------------------------------------------------------------
	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function getImageTransValue()
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
		return 0
	end

	local function tweenVisible(visible: boolean)
		local imgTrans = visible and getImageTransValue() or 1

		local f1 = rootGui:FindFirstChild("Frame1")
		local f2 = rootGui:FindFirstChild("Frame2")
		local label = rootGui:FindFirstChild("Label")

		if f1 and f1:FindFirstChild("ImageLabel") then
			TweenService:Create(f1.ImageLabel, fadeInfo, { ImageTransparency = imgTrans }):Play()
		end
		if f2 and f2:FindFirstChild("ImageLabel") then
			TweenService:Create(f2.ImageLabel, fadeInfo, { ImageTransparency = imgTrans }):Play()
		end

		if label and label:IsA("TextLabel") then
			label.Text = ("Press the %s key to escape!"):format(config.struggleKeybind and config.struggleKeybind.Name or "Space")
			TweenService:Create(label, TweenInfo.new(1), { TextTransparency = visible and 0 or 1 }):Play()
		end
	end

	----------------------------------------------------------------
	-- Percentage helper
	----------------------------------------------------------------
	local function findPercentageNumberValue(parent: Instance)
		local direct = parent:FindFirstChild("Percentage")
		if direct and direct:IsA("NumberValue") then
			return direct
		end
		for _, obj in ipairs(parent:GetDescendants()) do
			if obj.Name == "Percentage" and obj:IsA("NumberValue") then
				return obj
			end
		end
		return nil
	end

	local function setPercentagePct(pct: number)
		local pctObj = findPercentageNumberValue(rootGui)
		if not pctObj then
			pctObj = Instance.new("NumberValue")
			pctObj.Name = "Percentage"
			pctObj.Parent = rootGui
			dbg("Created Percentage NumberValue (fallback).")
		end
		pctObj.Value = math.clamp(pct, 0, 100)
	end

	----------------------------------------------------------------
	-- CLEANUP (the big fix)
	----------------------------------------------------------------
	local function exitStruggle(reason: string?)
		if not active and not currentStruggleRemote and not decreaseConn then
			-- still ensure actions are unbound even if state got desynced
			pcall(function() ContextActionService:UnbindAction(KEY_ACTION_NAME) end)
			pcall(function() ContextActionService:UnbindAction(MOUSE_ACTION_NAME) end)
			tweenVisible(false)
			return
		end

		dbg("ExitStruggle:", reason or "nil")

		active = false
		currentStruggleRemote = nil

		-- stop decay
		if decreaseConn then
			decreaseConn:Disconnect()
			decreaseConn = nil
		end

		-- IMPORTANT: always unbind so Space/Mouse1 return to normal
		pcall(function() ContextActionService:UnbindAction(KEY_ACTION_NAME) end)
		pcall(function() ContextActionService:UnbindAction(MOUSE_ACTION_NAME) end)

		-- reset progress UI
		progressValue = 0
		targetValue = 0
		setPercentagePct(0)

		-- hide UI
		tweenVisible(false)
	end

	----------------------------------------------------------------
	-- ContextAction callback
	----------------------------------------------------------------
	local function struggleAction(actionName, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Begin then return end
		if not active then return end

		progressValue += struggleIncrement
		if progressValue < 0 then progressValue = 0 end

		local pct = 0
		if targetValue > 0 then
			pct = (progressValue / targetValue) * 100
		end
		setPercentagePct(pct)

		dbg("Pressed struggle input. progress:", progressValue, "target:", targetValue, "pct:", pct)

		if progressValue >= targetValue then
			if currentStruggleRemote and currentStruggleRemote:IsA("RemoteEvent") then
				dbg("Firing struggle remote to server (success).")
				currentStruggleRemote:FireServer({ result = "Success" })
			else
				dbg("No valid struggle remote to fire.")
			end

			exitStruggle("success")
		end
	end

	local function startDecayLoop()
		if decreaseConn then
			decreaseConn:Disconnect()
			decreaseConn = nil
		end

		local elapsed = 0
		decreaseConn = RunService.Heartbeat:Connect(function(dt)
			if not active then return end
			elapsed += dt

			if elapsed >= struggleDecreaseInterval then
				elapsed -= struggleDecreaseInterval
				progressValue -= struggleDecreaseAmt
				if progressValue < 0 then progressValue = 0 end

				local pct = 0
				if targetValue > 0 then
					pct = (progressValue / targetValue) * 100
				end
				setPercentagePct(pct)
				dbg("Decay tick. progress:", progressValue, "pct:", pct)
			end
		end)
	end

	local function startStruggle(enemyPlayer, struggleRemote: RemoteEvent?)
		-- If enemyPlayer is nil, treat as END
		if not enemyPlayer then
			exitStruggle("server_end_nil_enemy")
			return
		end

		-- validate remote
		if struggleRemote and not struggleRemote:IsA("RemoteEvent") then
			warn("[Struggle] Received invalid struggle remote; ignoring.")
			struggleRemote = nil
		end

		-- cleanup previous session
		exitStruggle("restart")

		-- init
		active = true
		currentStruggleRemote = struggleRemote
		progressValue = 0
		targetValue = math.random(minStruggleValue, maxStruggleValue)
		setPercentagePct(0)

		dbg("Struggle started: target=", targetValue, "remote=", currentStruggleRemote and currentStruggleRemote.Name or "nil", "attacker=", tostring(enemyPlayer))

		-- choose input key
		local inputToBind: EnumItem? = nil
		if typeof(STRUGGLE_KEY) == "EnumItem" then
			inputToBind = STRUGGLE_KEY
		elseif type(STRUGGLE_KEY) == "string" then
			local ok, k = pcall(function() return Enum.KeyCode[STRUGGLE_KEY] end)
			if ok and k then inputToBind = k end
		end
		if not inputToBind then
			inputToBind = Enum.KeyCode.Space
		end

		-- Show UI now that we are active
		tweenVisible(true)

		-- bind inputs (steals Space/Mouse1 while active)
		ContextActionService:BindAction(KEY_ACTION_NAME, struggleAction, false, inputToBind)
		ContextActionService:BindAction(MOUSE_ACTION_NAME, struggleAction, false, Enum.UserInputType.MouseButton1)

		if struggleDecrease then
			startDecayLoop()
		end
	end

	----------------------------------------------------------------
	-- Server event: HasBeenGrappled
	----------------------------------------------------------------
	Remotes:WaitForChild("HasBeenGrappled").OnClientEvent:Connect(function(enemyPlayer, struggleRemoteName)
		-- If server sends nil/false to indicate end, cleanup immediately.
		if not enemyPlayer then
			exitStruggle("HasBeenGrappled_end")
			return
		end

		-- Validate name
		if type(struggleRemoteName) ~= "string" then
			warn("[Struggle] Expected remote name (string), got:", typeof(struggleRemoteName))
			return
		end

		if config.debugMode then
			print("[Struggle] HasBeenGrappled received. attacker:", enemyPlayer and tostring(enemyPlayer) or "nil", "remoteName:", struggleRemoteName)
		end

		-- Find struggle folder
		local struggleFolder = ReplicatedStorage:FindFirstChild("Struggle")
		if not struggleFolder then
			local ok, folder = pcall(function()
				return ReplicatedStorage:WaitForChild("Struggle", 2)
			end)
			struggleFolder = ok and folder or nil
		end
		if not struggleFolder then
			warn("[Struggle] Struggle folder not found in ReplicatedStorage")
			return
		end

		-- Find the remote by name
		local struggleRemote = struggleFolder:FindFirstChild(struggleRemoteName)
		if not struggleRemote then
			struggleRemote = struggleFolder:WaitForChild(struggleRemoteName, 5)
		end
		if not struggleRemote or not struggleRemote:IsA("RemoteEvent") then
			warn("[Struggle] Could not locate valid RemoteEvent named:", struggleRemoteName)
			return
		end

		startStruggle(enemyPlayer, struggleRemote)
	end)

	----------------------------------------------------------------
	-- FAILSAFE CLEANUPS
	----------------------------------------------------------------
	-- If you die/respawn while stuck, always clean up binds
	plr.CharacterAdded:Connect(function()
		exitStruggle("character_added_failsafe")
	end)

	-- Cleanup if UI removed
	rootGui.AncestryChanged:Connect(function()
		if not rootGui:IsDescendantOf(game) then
			exitStruggle("ui_removed")
		end
	end)

	-- Also do an initial cleanup in case something left binds behind before init
	exitStruggle("init_cleanup")
end

return M

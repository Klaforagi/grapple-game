-- LocalScript (client) - reliable struggle handler (ContextActionService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

-- Config
local minStruggleValue = config.minStruggleValue or 25
local maxStruggleValue = config.maxStruggleValue or 30
local struggleIncrement = config.struggleIncrement or 1
local struggleDecrease = config.struggleDecrease or true
local struggleDecreaseAmt = config.struggleDecreaseAmt or 1
local struggleDecreaseInterval = config.struggleDecreaseInterval or 1

local STRUGGLE_KEY = config.struggleKeybind or Enum.KeyCode.Space

-- state
local active = false
local progressValue = 0
local targetValue = 0
local decreaseConn = nil
local currentStruggleRemote = nil

-- unique action names
local KEY_ACTION_NAME = "STRUGGLE_KEY_" .. tostring(math.random(1,1e9))
local MOUSE_ACTION_NAME = "STRUGGLE_MOUSE_" .. tostring(math.random(1,1e9))

local function dbg(...)
	if config.debugMode then print("[Struggle]", ...) end
end


-- Tween settings
local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tweenVisible(visible)
	local goal = { ImageTransparency = visible and script.Parent.Percentage.ProgressScript.ImageTrans.Value or 1 }
	TweenService:Create(script.Parent.Frame1.ImageLabel, fadeInfo, goal):Play()
	TweenService:Create(script.Parent.Frame2.ImageLabel, fadeInfo, goal):Play()
	
	script.Parent.Label.Text = "Press the "..config.struggleKeybind.Name.." key to escape!"
	TweenService:Create(script.Parent.Label,TweenInfo.new(1),{TextTransparency = visible and 0 or 1}):Play()
end

-- helper: find a NumberValue named "Percentage" anywhere under parent
local function findPercentageNumberValue(parent)
	if not parent then return nil end
	-- quick direct find first
	local direct = parent:FindFirstChild("Percentage")
	if direct and direct:IsA("NumberValue") then
		return direct
	end
	-- else search descendants (fast enough for UI)
	for _, obj in ipairs(parent:GetDescendants()) do
		if obj.Name == "Percentage" and obj:IsA("NumberValue") then
			return obj
		end
	end
	return nil
end

local function setPercentagePct(pct)
	local pctObj = findPercentageNumberValue(script.Parent)
	if not pctObj then
		-- fallback: create under script.Parent if missing
		pctObj = Instance.new("NumberValue")
		pctObj.Name = "Percentage"
		pctObj.Parent = script.Parent
		dbg("Created Percentage NumberValue (fallback).")
	end
	pctObj.Value = math.clamp(pct, 0, 100)
end

-- ContextAction callback
local function struggleAction(actionName, inputState, inputObject)
	-- only on begin
	if inputState ~= Enum.UserInputState.Begin then return end
	if not active then return end

	-- increment progress
	progressValue = progressValue + struggleIncrement
	if progressValue < 0 then progressValue = 0 end

	-- update UI: represent as percent of targetValue (0..100)
	local pct = 0
	if targetValue > 0 then
		pct = (progressValue / targetValue) * 100
	end
	setPercentagePct(pct)

	dbg("Pressed struggle input. progress:", progressValue, "target:", targetValue, "pct:", pct)

	-- success
	if progressValue >= targetValue then
		if currentStruggleRemote and currentStruggleRemote:IsA("RemoteEvent") then
			dbg("Firing struggle remote to server (success).")
			-- you may want to send attacker info; server already checks sender identity
			currentStruggleRemote:FireServer({ result = "Success" })
		else
			dbg("No valid struggle remote to fire.")
		end

		-- cleanup: unbind inputs & stop decay
		active = false
		pcall(function() ContextActionService:UnbindAction(KEY_ACTION_NAME) end)
		pcall(function() ContextActionService:UnbindAction(MOUSE_ACTION_NAME) end)
		if decreaseConn then decreaseConn:Disconnect() decreaseConn = nil end
		currentStruggleRemote = nil
	end
end

local function startDecayLoop()
	if decreaseConn then decreaseConn:Disconnect() decreaseConn = nil end
	local elapsed = 0
	decreaseConn = RunService.Heartbeat:Connect(function(dt)
		if not active then return end
		elapsed = elapsed + dt
		if elapsed >= struggleDecreaseInterval then
			elapsed = elapsed - struggleDecreaseInterval
			progressValue = progressValue - struggleDecreaseAmt
			if progressValue < 0 then progressValue = 0 end
			local pct = 0
			if targetValue > 0 then pct = (progressValue / targetValue) * 100 end
			setPercentagePct(pct)
			dbg("Decay tick. progress:", progressValue, "pct:", pct)
		end
	end)
end

local function startStruggle(enemyPlayer, struggleRemote)
	-- validate remote
	if struggleRemote and not struggleRemote:IsA("RemoteEvent") then
		warn("[Struggle] Received invalid struggle remote; ignoring.")
		struggleRemote = nil
	end

	
	-- cleanup previous
	active = false
	if decreaseConn then decreaseConn:Disconnect() decreaseConn = nil end
	pcall(function() ContextActionService:UnbindAction(KEY_ACTION_NAME) end)
	pcall(function() ContextActionService:UnbindAction(MOUSE_ACTION_NAME) end)
	currentStruggleRemote = nil

	-- init
	active = true
	currentStruggleRemote = struggleRemote
	progressValue = 0
	targetValue = math.random(minStruggleValue, maxStruggleValue)
	setPercentagePct(0)
	dbg("Struggle started: target=", targetValue, "remote=", currentStruggleRemote and currentStruggleRemote.Name or "nil", "attacker=", tostring(enemyPlayer))

	-- bind key and mouse (ContextActionService ensures it fires even when GUIs are focused)
	local inputToBind = nil
	if typeof(STRUGGLE_KEY) == "EnumItem" then
		inputToBind = STRUGGLE_KEY
	elseif type(STRUGGLE_KEY) == "string" then
		-- try mapping string to KeyCode
		local ok, k = pcall(function() return Enum.KeyCode[STRUGGLE_KEY] end)
		if ok and k then inputToBind = k end
	end
	if not inputToBind then inputToBind = Enum.KeyCode.Space end

	ContextActionService:BindAction(KEY_ACTION_NAME, struggleAction, false, inputToBind)
	ContextActionService:BindAction(MOUSE_ACTION_NAME, struggleAction, false, Enum.UserInputType.MouseButton1)

	-- optional decay
	if struggleDecrease then
		startDecayLoop()
	end
end

-- handle server sending the NAME of the struggle remote instead of the instance
Remotes:WaitForChild("HasBeenGrappled").OnClientEvent:Connect(function(enemyPlayer, struggleRemoteName)
	
	tweenVisible(enemyPlayer and true or false)
	
	-- debug
	if config.debugMode then
		print("[Struggle] HasBeenGrappled received. attacker:", enemyPlayer and tostring(enemyPlayer) or "nil",
			"remoteName:", struggleRemoteName)
	end

	-- Validate we received a string name
	if type(struggleRemoteName) ~= "string" then
		warn("[Struggle] Expected remote name (string), got:", typeof(struggleRemoteName))
		return
	end

	

	-- Find the Struggle folder in ReplicatedStorage
	local struggleFolder = ReplicatedStorage:FindFirstChild("Struggle")
	if not struggleFolder then
		-- if the folder doesn't exist yet, try the WaitForChild case (in case server creates it later)
		-- but keep a short timeout to avoid hanging too long
		local ok, folder = pcall(function()
			return ReplicatedStorage:WaitForChild("Struggle", 2)
		end)
		struggleFolder = ok and folder or nil
	end

	if not struggleFolder then
		warn("[Struggle] Struggle folder not found in ReplicatedStorage")
		return
	end

	-- Try to find the RemoteEvent by name: fast find then WaitForChild short timeout
	local struggleRemote = struggleFolder:FindFirstChild(struggleRemoteName)
	if not struggleRemote then
		-- wait up to 5 seconds for the remote to appear (server might create it slightly before/after)
		struggleRemote = struggleFolder:WaitForChild(struggleRemoteName, 5)
	end

	if not struggleRemote or not struggleRemote:IsA("RemoteEvent") then
		warn("[Struggle] Could not locate valid RemoteEvent named:", struggleRemoteName)
		return
	end

	-- Now start the struggle, passing the RemoteEvent instance
	startStruggle(enemyPlayer, struggleRemote)
end)


-- Cleanup if script removed or player leaves UI
script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		active = false
		pcall(function() ContextActionService:UnbindAction(KEY_ACTION_NAME) end)
		pcall(function() ContextActionService:UnbindAction(MOUSE_ACTION_NAME) end)
		if decreaseConn then decreaseConn:Disconnect() decreaseConn = nil end
		currentStruggleRemote = nil
	end
end)

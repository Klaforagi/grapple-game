local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Storage = game:GetService("ReplicatedStorage")
local PlaySound = require(Storage:WaitForChild("Modules"):WaitForChild("PlaySound"))

local PULL_TIME = 0.5 -- Matches the crusher lever's downward stroke.
local COOLDOWN = 3 -- Measured from the start of each pull.
local READY_COLOR = Color3.fromRGB(0, 179, 0)
local LOCKED_COLOR = Color3.fromRGB(179, 0, 0)
local registered = {}

local function partNamed(parent, name)
	local part = parent:FindFirstChild(name, true)
	return part and part:IsA("BasePart") and part or nil
end

local function register(model)
	if registered[model] or not model:IsA("Model") or model.Name ~= "JailCellBig"
		or not model:IsDescendantOf(Workspace) then return end
	local lever = model:FindFirstChild("Lever", true)
	local roof = partNamed(model, "Roof")
	if not lever or not roof or roof:IsDescendantOf(lever) then return end
	local handle = partNamed(lever, "Handle")
	local connector1, connector2 = partNamed(lever, "Connector1"), partNamed(lever, "Connector2")
	local anchor = partNamed(lever, "Anchor")
	local trigger = partNamed(lever, "TriggerPart") or partNamed(lever, "TriggePart")
	if not handle or not connector1 or not connector2 or not anchor or not trigger then return end
	registered[model] = true
	anchor.Anchored, trigger.Anchored = true, true

	local leverParts = {}
	local function collect(part)
		local parts = part:GetConnectedParts(true)
		table.insert(parts, part)
		for _, connected in ipairs(parts) do
			if connected:IsDescendantOf(lever) and connected ~= anchor and connected ~= trigger
				and not leverParts[connected] then
				leverParts[connected] = connected.CFrame
				connected.Anchored = true
			end
		end
	end
	collect(connector1)
	collect(connector2)
	collect(handle)
	local hinge = CFrame.new((connector1.Position + connector2.Position) / 2) * connector1.CFrame.Rotation
	local pivot = lever:FindFirstChild("LeverPivot", true)
	if pivot and pivot:IsA("Attachment") then hinge = pivot.WorldCFrame end
	local axisName = model:GetAttribute("LeverAxis") or "Z"
	local axis = axisName == "Y" and Vector3.yAxis or axisName == "Z" and Vector3.zAxis or Vector3.xAxis
	local angle = model:GetAttribute("LeverAngle")
	if typeof(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = -90 end

	local roofAppearance = {
		Transparency = roof.Transparency,
		CanCollide = roof.CanCollide,
		CanTouch = roof.CanTouch,
		CanQuery = roof.CanQuery,
		CastShadow = roof.CastShadow,
	}
	local function setRoofVisible(visible)
		if visible then
			roof.Transparency = roofAppearance.Transparency
			roof.CastShadow = roofAppearance.CastShadow
			roof.CanQuery = roofAppearance.CanQuery
			roof.CanTouch = roofAppearance.CanTouch
			roof.CanCollide = roofAppearance.CanCollide
		else
			-- CanCollide must be off before Roblox allows CanQuery to be disabled.
			roof.CanCollide = false
			roof.CanTouch = false
			roof.CanQuery = false
			roof.CastShadow = false
			roof.Transparency = 1
		end
	end
	local function setLight(locked)
		local color = locked and LOCKED_COLOR or READY_COLOR
		anchor.Color = color
		for _, item in ipairs(lever:GetDescendants()) do
			if item:IsA("BasePart") and item.Name == "Light" then
				item.Color = color
			elseif item:IsA("Light") and (item:IsDescendantOf(anchor)
				or (item.Parent and item.Parent.Name == "Light")) then
				item.Color = color
			end
		end
	end
	local function leverPose(fraction)
		local transform = hinge * CFrame.fromAxisAngle(axis, math.rad(angle) * fraction) * hinge:Inverse()
		for part, original in pairs(leverParts) do
			if part.Parent then part.CFrame = transform * original end
		end
	end
	local function moveLever(from, to)
		local elapsed = 0
		while elapsed < PULL_TIME and model:IsDescendantOf(Workspace) do
			elapsed += RunService.Heartbeat:Wait()
			local fraction = TweenService:GetValue(math.clamp(elapsed / PULL_TIME, 0, 1),
				Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			leverPose(from + (to - from) * fraction)
		end
		if model:IsDescendantOf(Workspace) then leverPose(to) end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "JailRoofPrompt", "Pull Lever", "Jail Roof"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration, prompt.MaxActivationDistance = 0, 10
	prompt.RequiresLineOfSight, prompt.ClickablePrompt = false, true
	prompt.Parent = trigger
	local locked, busy, readyAt = false, false, 0
	leverPose(0)
	setRoofVisible(false)
	setLight(false)
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local now = os.clock()
		if busy or now < readyAt or not humanoid or humanoid.Health <= 0 or not root
			or humanoid:GetAttribute("CapsuleLocked")
			or (root.Position - trigger.Position).Magnitude > prompt.MaxActivationDistance + 2 then return end
		busy, prompt.Enabled = true, false
		readyAt = now + COOLDOWN
		local nextLocked = not locked
		local ok, err = pcall(function()
			setRoofVisible(nextLocked)
			setLight(nextLocked)
			local sounds = Storage:FindFirstChild("Sounds")
			local switch = sounds and sounds:FindFirstChild("Switch", true)
			if switch and switch:IsA("Sound") then PlaySound(anchor, switch) end
			moveLever(locked and 1 or 0, nextLocked and 1 or 0)
		end)
		if ok and model:IsDescendantOf(Workspace) and roof.Parent then
			locked = nextLocked
		else
			if roof.Parent then setRoofVisible(locked) end
			if lever.Parent then setLight(locked) end
			leverPose(locked and 1 or 0)
			if not ok then warn("[Jail Roof] " .. model:GetFullName() .. ": " .. tostring(err)) end
		end
		busy = false
		task.delay(math.max(0, readyAt - os.clock()), function()
			if model:IsDescendantOf(Workspace) and not busy then prompt.Enabled = true end
		end)
	end)
	model.Destroying:Once(function() registered[model] = nil end)
end

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(function()
		local ancestor = instance
		while ancestor and ancestor ~= Workspace do
			if ancestor:IsA("Model") and ancestor.Name == "JailCellBig" then register(ancestor) end
			ancestor = ancestor.Parent
		end
	end)
end)
for _, instance in ipairs(Workspace:GetDescendants()) do register(instance) end

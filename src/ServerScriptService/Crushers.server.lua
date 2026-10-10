local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Storage = game:GetService("ReplicatedStorage")
local PlaySound = require(Storage:WaitForChild("Modules"):WaitForChild("PlaySound"))
local Flatten = require(Storage.Modules:WaitForChild("CrusherFlatten"))

local DROP_DISTANCE = 14.4
local DROP_TIME = 1
local HOLD_TIME = 1.5
local RETURN_TIME = 4
local WARNING_TIME = 1
local READY_COLOR = Color3.fromRGB(0, 179, 0)
local BUSY_COLOR = Color3.fromRGB(179, 0, 0)
local registered = {}

local function partNamed(parent, name)
	local part = parent:FindFirstChild(name, true)
	return part and part:IsA("BasePart") and part or nil
end

local function killFromPart(part, groundY)
	local parent = part.Parent
	while parent and parent ~= Workspace do
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health > 0 then
				local ok, err = pcall(Flatten.Create, parent, groundY)
				if not ok then warn("[Crusher] Flatten effect: " .. tostring(err)) end
				-- Ragdolls disable state evaluation. Restore death processing as well
				-- as health so players and NPCs both actually die immediately.
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
				humanoid.EvaluateStateMachine = true
				humanoid.Health = 0
				humanoid:ChangeState(Enum.HumanoidStateType.Dead)
			end
			return
		end
		parent = parent.Parent
	end
end

local function register(model)
	if registered[model] or not model:IsA("Model") or model.Name ~= "Crusher"
		or not model:IsDescendantOf(Workspace) then return end
	local lever = model:FindFirstChild("Lever", true)
	local mover, smasher = partNamed(model, "Mover"), partNamed(model, "Smasher")
	if not lever or not mover or not smasher then return end
	local handle = partNamed(lever, "Handle")
	local connector1, connector2 = partNamed(lever, "Connector1"), partNamed(lever, "Connector2")
	local anchor = partNamed(lever, "Anchor")
	local trigger = partNamed(lever, "TriggerPart") or partNamed(lever, "TriggePart")
	if not handle or not connector1 or not connector2 or not anchor or not trigger then return end
	registered[model] = true
	anchor.Anchored, trigger.Anchored = true, true

	-- Move welded pieces together from their authored poses. Anchoring each
	-- driven piece also supports builds with an already-anchored Smasher.
	local moving, leverParts = {}, {}
	local function collect(part, destination, allowed)
		local parts = part:GetConnectedParts(true)
		table.insert(parts, part)
		for _, connected in ipairs(parts) do
			if allowed(connected) and not destination[connected] then
				destination[connected] = connected.CFrame
				connected.Anchored = true
			end
		end
	end
	local function movingAllowed(part)
		return part:IsDescendantOf(model) and not part:IsDescendantOf(lever) and part.Name ~= "Light"
	end
	collect(mover, moving, movingAllowed)
	collect(smasher, moving, movingAllowed)
	local bottomPose = moving[smasher]
	local groundY = bottomPose.Position.Y - DROP_DISTANCE - (math.abs(bottomPose.RightVector.Y) * smasher.Size.X
		+ math.abs(bottomPose.UpVector.Y) * smasher.Size.Y + math.abs(bottomPose.LookVector.Y) * smasher.Size.Z) / 2
	local function leverAllowed(part)
		return part:IsDescendantOf(lever) and part ~= anchor and part ~= trigger
	end
	collect(connector1, leverParts, leverAllowed)
	collect(connector2, leverParts, leverAllowed)
	collect(handle, leverParts, leverAllowed)
	local hinge = CFrame.new((connector1.Position + connector2.Position) / 2) * connector1.CFrame.Rotation
	-- Optional Attachment named LeverPivot overrides the inferred hinge.
	local pivot = lever:FindFirstChild("LeverPivot", true)
	if pivot and pivot:IsA("Attachment") then hinge = pivot.WorldCFrame end
	local axisName = model:GetAttribute("LeverAxis") or "Z"
	local axis = axisName == "Y" and Vector3.yAxis or axisName == "Z" and Vector3.zAxis or Vector3.xAxis
	local angle = model:GetAttribute("LeverAngle")
	if typeof(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = -90 end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "CrusherPrompt", "Pull Lever", "Crusher"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration, prompt.MaxActivationDistance = 0, 10
	prompt.RequiresLineOfSight, prompt.ClickablePrompt = false, true
	prompt.Parent = trigger
	local busy, lethal = false, false
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {model}
	local function status(active)
		local color = active and BUSY_COLOR or READY_COLOR
		anchor.Color = color
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("Light") and (item:IsDescendantOf(anchor)
				or (item.Parent and item.Parent.Name == "Light")) then item.Color = color end
		end
	end
	local function leverPose(fraction)
		local transform = hinge * CFrame.fromAxisAngle(axis, math.rad(angle) * fraction) * hinge:Inverse()
		for part, original in pairs(leverParts) do if part.Parent then part.CFrame = transform * original end end
	end
	local function move(distance)
		for part, original in pairs(moving) do
			if part.Parent then part.CFrame = original + Vector3.new(0, -distance, 0) end
		end
	end
	local function sweep(from, to)
		local steps = math.max(1, math.ceil((to.Position - from.Position).Magnitude / 0.5))
		for step = 0, steps do
			for _, part in ipairs(Workspace:GetPartBoundsInBox(from:Lerp(to, step / steps), smasher.Size, params)) do
				killFromPart(part, groundY)
			end
		end
	end
	local touched = smasher.Touched:Connect(function(part) if lethal then killFromPart(part, groundY) end end)
	status(false)
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if busy or not humanoid or humanoid.Health <= 0 or not root
			or humanoid:GetAttribute("CapsuleLocked")
			or (root.Position - trigger.Position).Magnitude > prompt.MaxActivationDistance + 2 then return end
		busy, lethal, prompt.Enabled = true, false, false
		status(true)
		local resetSound
		local ok, err = pcall(function()
			local sounds = Storage:FindFirstChild("Sounds")
			local alarm = sounds and sounds:FindFirstChild("Alarm", true)
			if alarm and alarm:IsA("Sound") then PlaySound(anchor, alarm) end
			local elapsed = -WARNING_TIME
			local impactPlayed = false
			local returning = false
			local function impact()
				if impactPlayed then return end
				impactPlayed = true
				local sounds = Storage:FindFirstChild("Sounds")
				local sound = sounds and sounds:FindFirstChild("Smash", true)
				if sound and sound:IsA("Sound") then PlaySound(smasher, sound) end
			end
			while elapsed < DROP_TIME + HOLD_TIME + RETURN_TIME do
				if not model:IsDescendantOf(Workspace) or not mover.Parent or not smasher.Parent then break end
				local dt = RunService.Heartbeat:Wait()
				local previous = smasher.CFrame
				elapsed += dt
				local leverElapsed = elapsed + WARNING_TIME
				local pull = leverElapsed < 0.5 and leverElapsed / 0.5 or math.max(0, 1 - (leverElapsed - 0.5) / 0.7)
				leverPose(TweenService:GetValue(pull, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
				-- The lever and warning begin immediately; the press stays harmless
				-- and fully raised until the one-second warning has finished.
				if elapsed < 0 then continue end
				if not impactPlayed then lethal = true end
				local distance
				if elapsed <= DROP_TIME then
					distance = DROP_DISTANCE * TweenService:GetValue(elapsed / DROP_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				elseif elapsed <= DROP_TIME + HOLD_TIME then
					distance = DROP_DISTANCE
				else
					local fraction = math.clamp((elapsed - DROP_TIME - HOLD_TIME) / RETURN_TIME, 0, 1)
					distance = DROP_DISTANCE * (1 - TweenService:GetValue(fraction, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
				end
				-- Finish the complete downstroke even after a long server frame.
				if not impactPlayed and elapsed >= DROP_TIME then
					move(DROP_DISTANCE)
					sweep(previous, smasher.CFrame)
					lethal = false
					impact()
				end
				if not returning and elapsed > DROP_TIME + HOLD_TIME then
					returning = true
					local library = Storage:FindFirstChild("Sounds")
					local sound = library and library:FindFirstChild("SmasherReset", true)
					if sound and sound:IsA("Sound") then
						resetSound = sound:Clone()
						resetSound.Looped = true
						resetSound.Parent = smasher
						resetSound:Play()
					end
				end
				move(distance)
				if lethal then sweep(previous, smasher.CFrame) end
			end
		end)
		if resetSound then
			resetSound:Stop()
			resetSound:Destroy()
		end
		lethal = false
		move(0)
		leverPose(0)
		status(false)
		busy, prompt.Enabled = false, true
		if not ok then warn("[Crusher] " .. model:GetFullName() .. ": " .. tostring(err)) end
	end)
	model.Destroying:Once(function()
		touched:Disconnect()
		registered[model] = nil
	end)
end

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(function()
		local ancestor = instance
		while ancestor and ancestor ~= Workspace do
			if ancestor:IsA("Model") and ancestor.Name == "Crusher" then register(ancestor) end
			ancestor = ancestor.Parent
		end
	end)
end)
for _, instance in ipairs(Workspace:GetDescendants()) do register(instance) end

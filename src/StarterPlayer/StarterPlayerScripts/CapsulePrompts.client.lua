local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local localPlayer = Players.LocalPlayer
local prompts = {}
local humanoids = {}
local animationLocks = {}
local animationBaselines = setmetatable({}, {__mode = "k"})

local function animationScripts(character)
	local scripts = {}
	for _, item in ipairs(character:GetDescendants()) do
		if (item:IsA("LocalScript") or item:IsA("Script")) and item.Name == "Animate" then
			table.insert(scripts, item)
		end
	end
	return scripts
end

local function updateAnimationLock(humanoid)
	local character = humanoid.Parent
	local locked = character and humanoid:GetAttribute("CapsuleLocked") == true
	local state = animationLocks[humanoid]
	if not locked then
		if state then
			for animate, wasDisabled in pairs(state.scripts) do
				if animate.Parent then animate.Disabled = wasDisabled end
			end
			animationLocks[humanoid] = nil
		elseif character then
			for _, animate in ipairs(animationScripts(character)) do
				animationBaselines[animate] = animate.Disabled
			end
		end
		return
	end

	if not state then
		state = {scripts = {}}
		animationLocks[humanoid] = state
	end
	for _, item in ipairs(animationScripts(character)) do
		if state.scripts[item] == nil then
			local baseline = animationBaselines[item]
			state.scripts[item] = if baseline == nil then false else baseline
		end
		item.Disabled = true
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
	end
end

local function distanceToPart(part, position)
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return Vector3.new(
		math.max(math.abs(point.X) - half.X, 0),
		math.max(math.abs(point.Y) - half.Y, 0),
		math.max(math.abs(point.Z) - half.Z, 0)
	).Magnitude
end

local function watch(instance)
	if instance:IsA("ProximityPrompt")
		and (instance.Name == "CapsulePrompt" or instance:GetAttribute("CapsulePrompt")) then
		prompts[instance] = true
	elseif instance:IsA("Humanoid") then
		humanoids[instance] = true
	end
end

workspace.DescendantAdded:Connect(watch)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end

-- Animation tracks are evaluated locally. Enforce the capsule lock immediately
-- before animation evaluation so the captive sees the same still pose as everyone else.
RunService.PreAnimation:Connect(function()
	for humanoid in pairs(humanoids) do updateAnimationLock(humanoid) end
end)

local accumulator = 0
local rescan = 0
RunService.Heartbeat:Connect(function(dt)
	rescan += dt
	if rescan >= 1 then
		rescan = 0
		for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
		for humanoid in pairs(humanoids) do
			if not humanoid:IsDescendantOf(workspace) then
				updateAnimationLock(humanoid)
				humanoids[humanoid] = nil
			end
		end
	end
	accumulator += dt
	if accumulator < 0.1 then return end
	accumulator = 0
	for prompt in pairs(prompts) do
		if not prompt:IsDescendantOf(workspace) then prompts[prompt] = nil continue end
		local reference = prompt:FindFirstChild("CapsuleModel")
		local model = reference and reference.Value or prompt:FindFirstAncestor("Capsule")
		local ownCharacter = localPlayer.Character
		local ownRoot = ownCharacter and ownCharacter:FindFirstChild("HumanoidRootPart")
		local ownHumanoid = ownCharacter and ownCharacter:FindFirstChildOfClass("Humanoid")
		if not model or not ownRoot or not ownHumanoid or ownHumanoid.Health <= 0
			or ownHumanoid:GetAttribute("CapsuleLocked")
			or distanceToPart(prompt.Parent, ownRoot.Position) > (Config.capsulePromptDistance or 10) then
			prompt.Enabled = false
			continue
		end
		local occupied = model and model:GetAttribute("CapsuleOccupied") == true
		local waitingForRespawn = model and model:GetAttribute("CapsuleWaitingForRespawn") == true
		local occupiedUserId = occupied and model:GetAttribute("CapsuleOccupiedUserId")
		if waitingForRespawn then
			prompt.Enabled = false
		elseif occupied then
			prompt.Enabled = occupiedUserId ~= localPlayer.UserId
		else
			local eligible = false
			for humanoid in pairs(humanoids) do
				local character = humanoid.Parent
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if character ~= localPlayer.Character and humanoid.Health > 0 and root
					and humanoid:GetAttribute("GrappledBy") == localPlayer.UserId
					and distanceToPart(prompt.Parent, root.Position) <= (Config.capsuleCaptureDistance or 12) then
					eligible = true
					break
				end
			end
			prompt.Enabled = eligible
		end
	end
end)

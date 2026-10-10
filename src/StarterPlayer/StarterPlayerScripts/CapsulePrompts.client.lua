local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local savedHealthGui

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

-- Transform is not replicated. Zero it after the animator writes, or this
-- client draws a straight bind pose over part positions the server still has tilted.
local function clearJointTransforms(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
	end
	for _, joint in ipairs(humanoid.Parent:GetDescendants()) do
		if joint:IsA("Motor6D") or joint:IsA("AnimationConstraint") then
			joint.Transform = CFrame.new()
		end
	end
	-- The server moves the body into the bind pose. Until that replicates, this
	-- client still has the hat at the ragdoll spot and the humanoid lets it fall.
	for _, accessory in ipairs(humanoid.Parent:GetChildren()) do
		if not (accessory:IsA("Accessory") or accessory:IsA("Hat") or accessory:IsA("Accoutrement")) then continue end
		local handle = accessory:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then continue end
		local weld
		for _, joint in ipairs(handle:GetDescendants()) do
			if joint:IsA("Weld") and (joint.Part0 == handle or joint.Part1 == handle)
				and typeof(joint.C0) == "CFrame" and typeof(joint.C1) == "CFrame" then
				weld = joint
				break
			end
		end
		if not weld then continue end
		local host, c0, c1
		if weld.Part1 == handle and weld.Part0 and weld.Part0:IsA("BasePart") then
			host, c0, c1 = weld.Part0, weld.C0, weld.C1
		elseif weld.Part0 == handle and weld.Part1 and weld.Part1:IsA("BasePart") then
			host, c0, c1 = weld.Part1, weld.C1, weld.C0
		end
		if host and typeof(host.CFrame) == "CFrame" then
			handle.CFrame = host.CFrame * c0 * c1:Inverse()
		end
	end
end

RunService.PreSimulation:Connect(function()
	for humanoid in pairs(animationLocks) do
		if humanoid.Parent and humanoid:GetAttribute("CapsuleLocked") then
			clearJointTransforms(humanoid)
		end
	end
end)
if RunService.PostSimulation then
	RunService.PostSimulation:Connect(function()
		for humanoid in pairs(animationLocks) do
			if humanoid.Parent and humanoid:GetAttribute("CapsuleLocked") then
				clearJointTransforms(humanoid)
			end
		end
	end)
end

local accumulator = 0
local rescan = 0
RunService.Heartbeat:Connect(function(dt)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local locked = humanoid and humanoid:GetAttribute("CapsuleLocked") == true
	pcall(function()
		if locked then
			if savedHealthGui == nil then savedHealthGui = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Health) end
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		elseif savedHealthGui ~= nil then
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, savedHealthGui)
			savedHealthGui = nil
		end
	end)
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
			or ownHumanoid:GetAttribute("GrapplePhysicsLocked") or ownHumanoid:GetAttribute("GrappledBy")
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

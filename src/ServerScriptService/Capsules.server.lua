local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Ragdoll = require(ReplicatedStorage.Modules:WaitForChild("RagdollService"))
local releaseGrapple = ServerStorage:FindFirstChild("ReleaseGrapple")
if not releaseGrapple then
	releaseGrapple = Instance.new("BindableEvent")
	releaseGrapple.Name = "ReleaseGrapple"
	releaseGrapple.Parent = ServerStorage
end

local FREEZE_COLOR = BrickColor.new("Medium blue").Color
local BODY_COLOR_PROPERTIES = {"HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3"}
local capsules = {}
local occupiedCharacters = setmetatable({}, {__mode = "k"})

local function normalizedName(instance)
	return string.lower(instance.Name):gsub("[%s_]", "")
end

local function findTrigger(model)
	for _, part in ipairs(model:GetDescendants()) do
		local name = normalizedName(part)
		if part:IsA("BasePart") and (name == "trigger" or name == "triggerpart") then return part end
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

local function markerCFrame(model, names)
	for _, name in ipairs(names) do
		local marker = model:FindFirstChild(name, true)
		if marker then
			if marker:IsA("Attachment") then return marker.WorldCFrame end
			if marker:IsA("BasePart") then return marker.CFrame end
		end
	end
end

local function captureCFrame(state, humanoid, root)
	local marker = markerCFrame(state.model, {"VictimPosition", "Victim Position", "InsidePoint", "Inside Point"})
	if marker then return marker end
	local platform = state.model:FindFirstChild("Platform", true)
	if platform and platform:IsA("BasePart") then
		local height = platform.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2
		local leg = humanoid.Parent:FindFirstChild("Left Leg")
		if leg and leg:IsA("BasePart") then height += leg.Size.Y end
		return platform.CFrame * CFrame.new(0, height, 0)
	end
	return state.model:GetPivot()
end

local function findGrappledVictim(owner, trigger)
	local closestCharacter, closestHumanoid, closestDistance
	for _, humanoid in ipairs(Workspace:GetDescendants()) do
		if not humanoid:IsA("Humanoid") then continue end
		local character = humanoid.Parent
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character ~= owner.Character and humanoid.Health > 0 and root
			and humanoid:GetAttribute("GrappledBy") == owner.UserId then
			local distance = distanceToPart(trigger, root.Position)
			if distance <= (Config.capsuleCaptureDistance or 12)
				and (not closestDistance or distance < closestDistance) then
				closestCharacter, closestHumanoid, closestDistance = character, humanoid, distance
			end
		end
	end
	return closestCharacter, closestHumanoid
end

local function updatePrompt(state)
	local occupied = state.occupant ~= nil
	local occupantPlayer = occupied and state.occupant.player
	local waiting = occupied and state.occupant.waitingForRespawn == true
	state.model:SetAttribute("CapsuleOccupied", occupied)
	state.model:SetAttribute("CapsuleWaitingForRespawn", waiting)
	state.model:SetAttribute("CapsuleOccupiedUserId", occupantPlayer and occupantPlayer.UserId or (occupied and 0 or nil))
	state.prompt.ActionText = waiting and "Waiting" or (occupied and "Save" or "Put Inside")
	state.prompt.ObjectText = waiting and "Waiting for respawn" or (occupied
		and ((occupantPlayer and occupantPlayer.DisplayName or state.occupant.character.Name) .. " is freezing") or "Capsule"
	)
end

local function updateHealth(occupant)
	local health = math.max(0, occupant.humanoid.Health)
	local maximum = math.max(1, occupant.humanoid.MaxHealth)
	if occupant.displayHealth == health and occupant.displayMax == maximum then return end
	occupant.displayHealth, occupant.displayMax = health, maximum
	occupant.healthText.Text = occupant.player and occupant.player.DisplayName or occupant.character.Name
	occupant.healthFill.Size = UDim2.fromScale(math.clamp(health / maximum, 0, 1), 1)
end

local function createHealthDisplay(occupant)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CapsuleHealth"
	gui.Adornee = occupant.root
	-- Scale units make the display naturally grow nearby and shrink with
	-- distance, unlike pixel offsets which remain the same screen size.
	gui.Size = UDim2.fromScale(5, 1.15)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.7)
	text.BackgroundColor3 = Color3.fromRGB(27, 42, 53)
	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Parent = gui
	local track = Instance.new("Frame")
	track.Size = UDim2.fromScale(1, 0.2)
	track.Position = UDim2.fromScale(0, 0.75)
	track.BackgroundColor3 = Color3.fromRGB(27, 42, 53)
	track.BorderSizePixel = 0
	track.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = FREEZE_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track
	occupant.healthGui, occupant.healthText, occupant.healthFill = gui, text, fill
	updateHealth(occupant)
	gui.Parent = occupant.character
end

local function straightenPose(occupant)
	local character = occupant.character
	local positioned = {[occupant.root] = true}
	local joints = {}
	for _, joint in ipairs(character:GetDescendants()) do
		local a, b, c0, c1
		if joint:IsA("Motor6D") then
			joint.Transform = CFrame.new()
			a, b, c0, c1 = joint.Part0, joint.Part1, joint.C0, joint.C1
		elseif joint:IsA("AnimationConstraint") and joint.Attachment0 and joint.Attachment1 then
			a, b = joint.Attachment0.Parent, joint.Attachment1.Parent
			c0, c1 = joint.Attachment0.CFrame, joint.Attachment1.CFrame
		end
		if a and b and a.Parent == character and b.Parent == character then
			table.insert(joints, {a, b, c0, c1})
		end
	end
	-- Anchored limbs cannot be repositioned by the restored animation joints.
	-- Place each body explicitly in its unanimated joint frame before freezing.
	for _ = 1, #joints do
		local changed = false
		for _, joint in ipairs(joints) do
			local a, b, c0, c1 = unpack(joint)
			if positioned[a] and not positioned[b] then
				b.CFrame = a.CFrame * c0 * c1:Inverse()
				positioned[b], changed = true, true
			elseif positioned[b] and not positioned[a] then
				a.CFrame = b.CFrame * c1 * c0:Inverse()
				positioned[a], changed = true, true
			end
		end
		if not changed then break end
	end
end

local function freezePose(occupant)
	for _, part in ipairs(occupant.character:GetDescendants()) do
		if part:IsA("BasePart") then
			if occupant.anchoredParts[part] == nil then occupant.anchoredParts[part] = part.Anchored end
			part.Anchored = true
		end
	end
	occupant.poseFrozen = true
end

local function restoreCharacter(state, rescued)
	local occupant = state.occupant
	if not occupant then return end
	state.occupant = nil
	occupiedCharacters[occupant.character] = nil
	for _, connection in ipairs(occupant.connections) do connection:Disconnect() end
	if occupant.healthGui then occupant.healthGui:Destroy() end
	for scriptInstance, wasDisabled in pairs(occupant.animationScripts) do
		if scriptInstance.Parent then scriptInstance.Disabled = wasDisabled end
	end

	local humanoid, root = occupant.humanoid, occupant.root
	if humanoid.Parent == occupant.character then
		humanoid:SetAttribute("CapsuleLocked", nil)
		humanoid.BreakJointsOnDeath = occupant.breakJointsOnDeath
		humanoid.WalkSpeed = occupant.walkSpeed
		-- Capture starts during grapple ragdoll, where AutoRotate is temporarily false.
		humanoid.AutoRotate = true
		humanoid.UseJumpPower = occupant.useJumpPower
		humanoid.JumpPower = occupant.jumpPower
		humanoid.JumpHeight = occupant.jumpHeight
	end
	-- Freezing permanently recolors this character. Only a fresh respawn
	-- restores its normal appearance, including for rescued NPCs.
	for _, tool in ipairs(occupant.detachedTools) do
		if tool.Parent == nil and occupant.character.Parent then tool.Parent = occupant.character end
	end
	for part, wasAnchored in pairs(occupant.anchoredParts) do
		if part.Parent then part.Anchored = wasAnchored end
	end
	if root.Parent == occupant.character then
		root.Anchored = occupant.rootAnchored
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if rescued and humanoid.Health > 0 then
			local exit = markerCFrame(state.model, {"ExitPoint", "Exit Point"})
				or state.trigger.CFrame * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, -(state.trigger.Size.Z / 2 + 3))
			root.CFrame = exit
			pcall(function() root:SetNetworkOwnershipAuto() end)
		end
	end
	updatePrompt(state)
end

local function capture(state, owner, character, humanoid)
	if state.occupant or occupiedCharacters[character] then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root.Anchored then return end

	local occupant = {
		player = Players:GetPlayerFromCharacter(character), character = character, humanoid = humanoid, root = root,
		walkSpeed = humanoid.WalkSpeed, autoRotate = humanoid.AutoRotate,
		useJumpPower = humanoid.UseJumpPower, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight,
		rootAnchored = root.Anchored, anchoredParts = {}, bodyColors = {}, animationScripts = {}, connections = {}, detachedTools = {},
		breakJointsOnDeath = humanoid.BreakJointsOnDeath,
		nextDamageAt = os.clock() + 1,
	}
	state.occupant = occupant
	occupiedCharacters[character] = state
	humanoid:SetAttribute("CapsuleLocked", true)
	humanoid.BreakJointsOnDeath = false
	humanoid:SetAttribute("ForcedRagdollUntil", nil)
	releaseGrapple:Fire(owner)
	if occupant.player then
		humanoid:UnequipTools()
	else
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(occupant.detachedTools, child)
				child.Parent = nil
			end
		end
	end
	humanoid.WalkSpeed, humanoid.AutoRotate = 0, false
	humanoid.JumpPower, humanoid.JumpHeight = 0, 0
	for _, item in ipairs(character:GetDescendants()) do
		if (item:IsA("LocalScript") or item:IsA("Script")) and item.Name == "Animate" then
			occupant.animationScripts[item] = item.Disabled
			item.Disabled = true
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
	end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Color = FREEZE_COLOR
		end
	end
	-- Update the skin palette as well as the physical parts for this life.
	local function freezePalette(item)
		if not item:IsA("BodyColors") or occupant.bodyColors[item] then return end
		for _, property in ipairs(BODY_COLOR_PROPERTIES) do
			item[property] = FREEZE_COLOR
		end
		occupant.bodyColors[item] = true
	end
	for _, item in ipairs(character:GetChildren()) do freezePalette(item) end
	table.insert(occupant.connections, character.ChildAdded:Connect(freezePalette))
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	root.CFrame = captureCFrame(state, humanoid, root)
	root.Anchored = true
	createHealthDisplay(occupant)

	local backpack = occupant.player and occupant.player:FindFirstChildOfClass("Backpack")
	table.insert(occupant.connections, character.ChildAdded:Connect(function(child)
		if not child:IsA("Tool") then return end
		if backpack then
			child.Parent = backpack
		elseif not table.find(occupant.detachedTools, child) then
			table.insert(occupant.detachedTools, child)
			child.Parent = nil
		end
	end))
	table.insert(occupant.connections, humanoid.Died:Connect(function()
		if state.occupant ~= occupant then return end
		freezePose(occupant)
		occupant.waitingForRespawn = true
		updatePrompt(state)
	end))
	if occupant.player then
		table.insert(occupant.connections, occupant.player.CharacterRemoving:Connect(function(removed)
			if removed == character and state.occupant == occupant and not occupant.waitingForRespawn then
				restoreCharacter(state, false)
			end
		end))
		table.insert(occupant.connections, occupant.player.CharacterAdded:Connect(function(added)
			if added ~= character and state.occupant == occupant and occupant.waitingForRespawn then
				restoreCharacter(state, false)
			end
		end))
	end
	updatePrompt(state)

	-- Grapple handoff clears shortly after the rope is removed. Restore the
	-- animated joints while the anchored capsule state continues to immobilize.
	task.delay(math.max(0.3, (Config.playerOwnershipReleaseDelay or 0.2) + 0.1), function()
		if state.occupant ~= occupant or humanoid.Health <= 0 then return end
		humanoid:SetAttribute("ForcedRagdollUntil", nil)
		humanoid:SetAttribute("FallRagdollUntil", nil)
		humanoid:SetAttribute("BombRagdollUntil", nil)
		humanoid:RemoveTag("Ragdoll")
		Ragdoll.Set(humanoid, false, true)
		-- Recovery restores AutoRotate and reconnects the limbs. Reapply the
		-- capsule pose only after those joints have been restored.
		humanoid.AutoRotate = false
		root.CFrame = captureCFrame(state, humanoid, root)
		straightenPose(occupant)
		freezePose(occupant)
	end)
end

local function configure(model)
	if capsules[model] or not model:IsA("Model") or normalizedName(model) ~= "capsule" then return end
	local trigger = findTrigger(model)
	if not trigger then return end
	local prompt = trigger:FindFirstChild("CapsulePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CapsulePrompt"
		prompt:SetAttribute("CapsulePrompt", true)
		prompt.Parent = trigger
	end
	prompt.ActionText = "Put Inside"
	prompt.Enabled = true
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.HoldDuration = 0
	prompt.ObjectText = "Capsule"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = (Config.capsulePromptDistance or 10) + trigger.Size.Magnitude / 2
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt:SetAttribute("CapsulePrompt", true)
	local state = {model = model, trigger = trigger, prompt = prompt}
	local modelReference = Instance.new("ObjectValue")
	modelReference.Name = "CapsuleModel"
	modelReference.Value = model
	modelReference.Parent = prompt
	capsules[model] = state
	updatePrompt(state)
	prompt.Triggered:Connect(function(player)
		local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local actor = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not actor or actor.Health <= 0 or actor:GetAttribute("CapsuleLocked")
			or actor:GetAttribute("GrapplePhysicsLocked") or actor:GetAttribute("GrappledBy") then return end
		if not playerRoot or distanceToPart(trigger, playerRoot.Position) > (Config.capsulePromptDistance or 10) + 2 then return end
		if state.occupant then
			if state.occupant.waitingForRespawn then return end
			if not state.occupant.player or state.occupant.player ~= player then restoreCharacter(state, true) end
			return
		end
		local character, humanoid = findGrappledVictim(player, trigger)
		if character and humanoid then capture(state, player, character, humanoid) end
	end)
	model.Destroying:Connect(function()
		if state.occupant then restoreCharacter(state, true) end
		capsules[model] = nil
	end)
end

for _, instance in ipairs(Workspace:GetDescendants()) do configure(instance) end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") and instance.Name == "Capsule" then
		task.defer(configure, instance)
	elseif instance.Name == "Trigger Part" or instance.Name == "TriggerPart" then
		local model = instance:FindFirstAncestor("Capsule")
		if model then task.defer(configure, model) end
	end
end)

-- Reconcile models assembled or renamed after insertion, and clean up mobs
-- removed without a Died event. No per-captive coroutine can outlive its rig.
local scanElapsed = 0
RunService.Heartbeat:Connect(function(dt)
	scanElapsed += dt
	if scanElapsed >= 1 then
		scanElapsed = 0
		for _, instance in ipairs(Workspace:GetDescendants()) do configure(instance) end
	end
	for model, state in pairs(capsules) do
		local occupant = state.occupant
		if not model:IsDescendantOf(Workspace) or not state.prompt:IsDescendantOf(model) then
			if occupant then restoreCharacter(state, true) end
			capsules[model] = nil
		elseif occupant then
			if occupant.poseFrozen then freezePose(occupant) end
			if not occupant.character:IsDescendantOf(Workspace) then
				if occupant.waitingForRespawn and occupant.player and occupant.player.Parent == Players then continue end
				restoreCharacter(state, false)
			elseif occupant.humanoid.Health <= 0 then
				if not occupant.waitingForRespawn then
					occupant.waitingForRespawn = true
					updatePrompt(state)
				end
			elseif os.clock() >= occupant.nextDamageAt then
				occupant.nextDamageAt = os.clock() + 1
				occupant.humanoid:TakeDamage(Config.capsuleDamagePerSecond or 5)
			end
			local animator = occupant.humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
			end
			if state.occupant == occupant then updateHealth(occupant) end
		end
	end
end)


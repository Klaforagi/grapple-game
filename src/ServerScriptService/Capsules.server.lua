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

-- Assigned below once joint measurement exists. R6 HipHeight is often 0 even
-- though the legs extend below the root; adding that on top of a real HipHeight
-- puts the rig through the capsule ceiling.
local bindFootDrop
local function captureCFrame(state, humanoid, root)
	local marker = markerCFrame(state.model, {"VictimPosition", "Victim Position", "InsidePoint", "Inside Point"})
	if marker then return marker end
	local platform = state.model:FindFirstChild("Platform", true)
	if platform and platform:IsA("BasePart") then
		local drop = bindFootDrop(humanoid.Parent, root)
		return platform.CFrame * CFrame.new(0, platform.Size.Y / 2 + drop, 0)
	end
	return state.model:GetPivot()
end

-- Motor6D.Transform is not replicated. The captive's client can draw a straight
-- bind pose while the server still has the ragdoll's tilted part positions.
local function upright(cf)
	if typeof(cf) ~= "CFrame" then return cf end
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then
		local right = cf.RightVector
		flat = Vector3.new(right.Z, 0, -right.X)
	end
	if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(cf.Position, cf.Position + flat.Unit)
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

-- Attachment.CFrame is relative to its parent, which may be a bone rather than the limb.
local function offsetInPart(attachment, part)
	local cf = attachment.CFrame
	if typeof(cf) ~= "CFrame" or not part then return cf end
	local current = attachment.Parent
	while current and current ~= part do
		if current:IsA("BasePart") then break end
		if current:IsA("Attachment") or current:IsA("Bone") then
			local parentFrame = current.CFrame
			if typeof(parentFrame) == "CFrame" then cf = parentFrame * cf end
		end
		current = current.Parent
	end
	return cf
end

local function inRagdollFolder(joint)
	local parent = joint.Parent
	while parent do
		if parent.Name == "GrappleRagdollJoints" then return true end
		parent = parent.Parent
	end
end

-- R6's PrimaryPart is the Head, not the HumanoidRootPart. Anchoring that head
-- (or any other non-root limb) makes the engine drop the body's CFrame, so the
-- rig stays where the grapple let go while the loose root still sits in the capsule.
local function rigIsR6(character, humanoid)
	local rigTypes = Enum.HumanoidRigType
	if rigTypes and humanoid and humanoid.RigType == rigTypes.R6 then return true end
	return character and character:FindFirstChild("Torso") ~= nil
		and not character:FindFirstChild("LowerTorso")
		and not character:FindFirstChild("UpperTorso")
end

local function isOwnedByCharacter(part, character)
	if not part or not part.IsA or not part:IsA("BasePart") then return false end
	local current = part.Parent
	while current and current ~= character do
		if (current.IsA and (current:IsA("Accessory") or current:IsA("Hat") or current:IsA("Accoutrement") or current:IsA("Tool")))
			or current.Name == "GrappleRagdollJoints" or current.Name == "GrappleSelfCollision" then
			return false
		end
		current = current.Parent
	end
	return current == character
end

local function nearestBodyPart(instance, character)
	local current = instance
	while current and current ~= character do
		if current.IsA and current:IsA("BasePart") and isOwnedByCharacter(current, character) then return current end
		current = current.Parent
	end
end

local function collectPoseJoints(character, kinematic)
	local motors, welds = {}, {}
	local function push(list, a, b, c0, c1)
		if isOwnedByCharacter(a, character) and isOwnedByCharacter(b, character)
			and typeof(c0) == "CFrame" and typeof(c1) == "CFrame" then
			table.insert(list, {a, b, c0, c1})
		end
	end
	for _, joint in ipairs(character:GetDescendants()) do
		if inRagdollFolder(joint) then continue end
		if joint:IsA("Motor6D") then
			if kinematic then joint.Transform = CFrame.new() end
			push(motors, joint.Part0, joint.Part1, joint.C0, joint.C1)
		elseif joint:IsA("AnimationConstraint") and joint.Attachment0 and joint.Attachment1 then
			-- A kinematic animation joint keeps drawing the local pose after the
			-- part CFrames are frozen, which is how the captive stays straight
			-- on their own screen while everyone else sees the tilt.
			if kinematic then
				joint.Transform = CFrame.new()
				if kinematic[joint] == nil then kinematic[joint] = joint.IsKinematic end
				joint.IsKinematic = false
			end
			local a = nearestBodyPart(joint.Attachment0, character)
			local b = nearestBodyPart(joint.Attachment1, character)
			push(motors, a, b, offsetInPart(joint.Attachment0, a), offsetInPart(joint.Attachment1, b))
		elseif joint:IsA("Weld") then
			-- Custom R6 rigs often glue limbs with welds instead of motors.
			-- Motors are applied first so a leftover weld cannot freeze the ragdoll pose.
			push(welds, joint.Part0, joint.Part1, joint.C0, joint.C1)
		end
	end
	for _, joint in ipairs(welds) do table.insert(motors, joint) end
	return motors
end

local function straightenPose(occupant)
	local joints = collectPoseJoints(occupant.character, occupant.kinematic)
	local positioned = {[occupant.root] = true}
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

local function fallbackDrop(humanoid, root)
	local hip = humanoid and tonumber(humanoid.HipHeight) or 0
	local half = (root and root.Size and root.Size.Y or 2) / 2
	if hip > 0 then return hip + half end
	local character = humanoid and humanoid.Parent
	if character then
		for _, name in ipairs({"Left Leg", "Right Leg", "LeftLeg", "RightLeg", "LeftLowerLeg", "RightLowerLeg"}) do
			local leg = character:FindFirstChild(name)
			if leg and leg:IsA("BasePart") and leg.Size then return leg.Size.Y + half end
		end
	end
	return half + 2
end

local function relativeBottom(root, joints)
	local relative = {[root] = CFrame.new()}
	for _ = 1, #joints do
		local changed = false
		for _, joint in ipairs(joints) do
			local a, b, c0, c1 = unpack(joint)
			if relative[a] and not relative[b] then
				relative[b] = relative[a] * c0 * c1:Inverse()
				changed = true
			elseif relative[b] and not relative[a] then
				relative[a] = relative[b] * c1 * c0:Inverse()
				changed = true
			end
		end
		if not changed then break end
	end
	local lowest
	for part, cf in pairs(relative) do
		if part ~= root and typeof(cf) == "CFrame" and cf.Position and part.Size then
			local bottom = cf.Position.Y - part.Size.Y / 2
			if not lowest or bottom < lowest then lowest = bottom end
		end
	end
	return lowest
end

bindFootDrop = function(character, root)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root then return fallbackDrop(humanoid, root) end
	local lowest = relativeBottom(root, collectPoseJoints(character))
	if not lowest then return fallbackDrop(humanoid, root) end
	return math.clamp(-lowest, (root.Size and root.Size.Y or 2) / 2, 30)
end

local function eachAccessory(character)
	local list = {}
	for _, item in ipairs(character:GetDescendants()) do
		if (item:IsA("Accessory") or item:IsA("Hat") or item:IsA("Accoutrement"))
			and not item:FindFirstAncestorOfClass("Tool") then
			table.insert(list, item)
		end
	end
	return list
end

local function suppressHandleConstraints(occupant, handle)
	for _, joint in ipairs(occupant.character:GetDescendants()) do
		local hit = false
		if joint:IsA("WeldConstraint") then
			hit = joint.Part0 == handle or joint.Part1 == handle
		elseif joint:IsA("RigidConstraint") and joint.Attachment0 and joint.Attachment1 then
			hit = joint.Attachment0.Parent == handle or joint.Attachment1.Parent == handle
		end
		if hit then
			-- These constraints keep the offset from the moment physics last
			-- solved them. After the head is moved they drag the hat off.
			if occupant.disabledConstraints[joint] == nil then
				occupant.disabledConstraints[joint] = joint.Enabled ~= false
			end
			joint.Enabled = false
		end
	end
end

-- Record the authored offset before the head is teleported. The humanoid
-- deletes AccessoryWeld when that teleport leaves the handle behind.
local function describeAccessory(occupant, accessory, allowLive)
	local character, handle = occupant.character, accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end
	local host, c0, c1, weld
	for _, joint in ipairs(character:GetDescendants()) do
		if not (joint:IsA("Weld") or joint:IsA("Motor6D")) then continue end
		if (joint.Part0 ~= handle and joint.Part1 ~= handle)
			or typeof(joint.C0) ~= "CFrame" or typeof(joint.C1) ~= "CFrame" then
			continue
		end
		if joint.Part1 == handle and isOwnedByCharacter(joint.Part0, character) then
			host, c0, c1 = joint.Part0, joint.C0, joint.C1
			if joint:IsA("Weld") then weld = joint end
			break
		elseif joint.Part0 == handle and isOwnedByCharacter(joint.Part1, character) then
			host, c0, c1 = joint.Part1, joint.C1, joint.C0
			if joint:IsA("Weld") then weld = joint end
			break
		end
	end
	if not host then
		for _, joint in ipairs(character:GetDescendants()) do
			if not (joint:IsA("RigidConstraint") and joint.Attachment0 and joint.Attachment1) then continue end
			local p0, p1 = joint.Attachment0.Parent, joint.Attachment1.Parent
			if p0 ~= handle and p1 ~= handle then continue end
			local body = nearestBodyPart(p0 == handle and p1 or p0, character)
			local bodyAtt = p0 == handle and joint.Attachment1 or joint.Attachment0
			local handleAtt = p0 == handle and joint.Attachment0 or joint.Attachment1
			if body and typeof(bodyAtt.CFrame) == "CFrame" and typeof(handleAtt.CFrame) == "CFrame" then
				host, c0, c1 = body, offsetInPart(bodyAtt, body), offsetInPart(handleAtt, handle)
				break
			end
		end
	end
	if not host then
		for _, attachment in ipairs(handle:GetChildren()) do
			if not attachment:IsA("Attachment") or typeof(attachment.CFrame) ~= "CFrame" then continue end
			for _, candidate in ipairs(character:GetDescendants()) do
				if candidate == attachment or not candidate:IsA("Attachment") or candidate.Name ~= attachment.Name
					or typeof(candidate.CFrame) ~= "CFrame" then
					continue
				end
				local body = nearestBodyPart(candidate, character)
				if body and body ~= handle then
					host, c0, c1 = body, offsetInPart(candidate, body), offsetInPart(attachment, handle)
					break
				end
			end
			if host then break end
		end
	end
	if not host then
		local head, pos = character:FindFirstChild("Head"), accessory.AttachmentPos
		if head and head:IsA("BasePart") and typeof(pos) == "Vector3" then
			local up = typeof(accessory.AttachmentUp) == "Vector3" and accessory.AttachmentUp.Magnitude > 0
				and accessory.AttachmentUp or Vector3.yAxis
			local forward = typeof(accessory.AttachmentForward) == "Vector3" and accessory.AttachmentForward.Magnitude > 0
				and accessory.AttachmentForward or Vector3.zAxis
			local right = forward:Cross(up)
			if up.Magnitude > 0.001 and right.Magnitude > 0.001 then
				host, c0 = head, CFrame.new(0, head.Size.Y / 2, 0)
				c1 = CFrame.fromMatrix(pos, right.Unit, up.Unit)
			end
		end
	end
	if not host and allowLive then
		for _, joint in ipairs(character:GetDescendants()) do
			if not joint:IsA("WeldConstraint") or (joint.Part0 ~= handle and joint.Part1 ~= handle) then continue end
			local other = joint.Part0 == handle and joint.Part1 or joint.Part0
			if not isOwnedByCharacter(other, character) or typeof(other.CFrame) ~= "CFrame"
				or typeof(handle.CFrame) ~= "CFrame" then
				continue
			end
			local distance = (handle.Position - other.Position).Magnitude
			if distance <= math.max(other.Size.Magnitude + handle.Size.Magnitude, 6) then
				host, c0, c1 = other, other.CFrame:Inverse() * handle.CFrame, CFrame.new()
				break
			end
		end
	end
	if not host or typeof(c0) ~= "CFrame" or typeof(c1) ~= "CFrame" then return end
	return {handle = handle, host = host, c0 = c0, c1 = c1, weld = weld}
end

local function rememberAccessories(occupant, allowLive)
	for _, accessory in ipairs(eachAccessory(occupant.character)) do
		if not occupant.accessories[accessory] then
			local described = describeAccessory(occupant, accessory, allowLive)
			if described then occupant.accessories[accessory] = described end
		end
	end
end

local function applyAccessories(occupant)
	if not occupant.character then return end
	for accessory, saved in pairs(occupant.accessories) do
		local handle, host, c0, c1 = saved.handle, saved.host, saved.c0, saved.c1
		if not accessory.Parent or not handle.Parent or not host.Parent
			or typeof(c0) ~= "CFrame" or typeof(c1) ~= "CFrame" or typeof(host.CFrame) ~= "CFrame" then
			continue
		end
		suppressHandleConstraints(occupant, handle)
		local weld = saved.weld
		if not weld or not weld.Parent or not weld:IsA("Weld") then
			weld = handle:FindFirstChild("AccessoryWeld")
			if not weld or not weld:IsA("Weld") then
				weld = Instance.new("Weld")
				weld.Name = "AccessoryWeld"
				weld.Parent = handle
				saved.created = true
			end
			saved.weld = weld
		end
		weld.Part0, weld.Part1 = host, handle
		weld.C0, weld.C1 = c0, c1
		weld.Enabled = true
		if not occupant.handleProps[handle] then
			occupant.handleProps[handle] = {collide = handle.CanCollide, massless = handle.Massless}
		end
		handle.CanCollide = false
		handle.Massless = true
		handle.AssemblyLinearVelocity = Vector3.zero
		handle.AssemblyAngularVelocity = Vector3.zero
		-- An R6 limb or hat CFrame write is rerouted to the HumanoidRootPart and
		-- leaves the visible body where it was. The weld holds the hat; the rig
		-- move below carries every part together.
		if not rigIsR6(occupant.character, occupant.humanoid) then
			handle.CFrame = host.CFrame * c0 * c1:Inverse()
		end
	end
end

local function requestRespawn(humanoid)
	local request = ServerStorage:FindFirstChild("RigRespawnRequest")
	if request then pcall(function() request:Fire(humanoid) end) end
end

local function freezePose(occupant)
	local r6 = rigIsR6(occupant.character, occupant.humanoid)
	for _, part in ipairs(occupant.character:GetDescendants()) do
		if part:IsA("BasePart") then
			if occupant.anchoredParts[part] == nil then occupant.anchoredParts[part] = part.Anchored end
			-- Only the assembly root may be anchored on R6. Anchoring the Head,
			-- torso, or a limb drops replication of the teleport.
			part.Anchored = not r6 or part == occupant.root
		end
	end
	occupant.poseFrozen = true
end

-- The player who closed the capsule owns the freeze, including after the
-- grapple that carried them in has already been released.
local function markFreeze(occupant)
	local humanoid = occupant.humanoid
	if not humanoid or humanoid:GetAttribute("DeathCause") then return end
	humanoid:SetAttribute("DeathCause", "Freeze")
	if type(occupant.captorId) == "number" then
		humanoid:SetAttribute("DeathFreezer", occupant.captorId)
	end
end

-- Health reaching 0 does not emit Died while EvaluateStateMachine is off, so
-- an NPC rig would stay in the capsule and never respawn.
local function finishOccupantDeath(state, occupant)
	if occupant.deathFinished or state.occupant ~= occupant then return end
	occupant.deathFinished = true
	freezePose(occupant)
	occupant.waitingForRespawn = true
	updatePrompt(state)
	local humanoid = occupant.humanoid
	if humanoid.Parent ~= occupant.character then
		if not occupant.player then requestRespawn(humanoid) end
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	humanoid.EvaluateStateMachine = true
	if humanoid.Health > 0 then
		markFreeze(occupant)
		humanoid.Health = 0
	elseif humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
		-- Health is already 0, so writing 0 again does not emit Died. A one-point
		-- pulse is what makes an NPC rig actually enter Dead and respawn.
		humanoid.BreakJointsOnDeath = false
		humanoid.Health = humanoid.Health + 1
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.Health = 0
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	applyAccessories(occupant)
	if not occupant.player then requestRespawn(humanoid) end
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
	for joint, wasKinematic in pairs(occupant.kinematic) do
		if joint.Parent then joint.IsKinematic = wasKinematic end
	end
	for _, saved in pairs(occupant.accessories) do
		if not (saved.created and saved.weld and saved.weld.Parent) then continue end
		local held = false
		for joint in pairs(occupant.disabledConstraints) do
			local handle = saved.handle
			if joint:IsA("WeldConstraint") and (joint.Part0 == handle or joint.Part1 == handle) then
				held = true
			elseif joint:IsA("RigidConstraint") and joint.Attachment0 and joint.Attachment1
				and (joint.Attachment0.Parent == handle or joint.Attachment1.Parent == handle) then
				held = true
			end
		end
		-- A weld we had to create is the only thing holding a classic hat on.
		-- Drop it only when the original constraint will take over again.
		if held then saved.weld:Destroy() end
	end
	for joint, wasEnabled in pairs(occupant.disabledConstraints) do
		if joint.Parent then joint.Enabled = wasEnabled end
	end
	for handle, props in pairs(occupant.handleProps) do
		if handle.Parent then
			handle.CanCollide, handle.Massless = props.collide, props.massless
		end
	end

	local humanoid, root = occupant.humanoid, occupant.root
	if humanoid.Parent == occupant.character then
		humanoid:SetAttribute("CapsuleLocked", nil)
		humanoid.BreakJointsOnDeath = occupant.breakJointsOnDeath
		humanoid.WalkSpeed = occupant.walkSpeed
		-- Capture starts during grapple ragdoll, where AutoRotate is temporarily false.
		humanoid.AutoRotate = true
		humanoid.EvaluateStateMachine = occupant.evaluateStateMachine
		humanoid.PlatformStand = occupant.platformStand == true
		if occupant.gettingUp ~= nil then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, occupant.gettingUp)
		end
		humanoid.UseJumpPower = occupant.useJumpPower
		humanoid.JumpPower = occupant.jumpPower
		humanoid.JumpHeight = occupant.jumpHeight
		if typeof(occupant.requiresNeck) == "boolean" then humanoid.RequiresNeck = occupant.requiresNeck end
		if typeof(occupant.scalingEnabled) == "boolean" then
			humanoid.AutomaticScalingEnabled = occupant.scalingEnabled
		end
		humanoid:SetAttribute("PhysicsServerUntil", nil)
		if rescued and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end
	-- Freezing permanently recolors this character. Only a fresh respawn
	-- restores its normal appearance, including for rescued NPCs.
	for _, tool in ipairs(occupant.detachedTools) do
		if tool.Parent == nil and occupant.character.Parent then tool.Parent = occupant.character end
	end
	for part, wasAnchored in pairs(occupant.anchoredParts) do
		if part.Parent then part.Anchored = wasAnchored end
	end
	if occupant.savedPrimary and occupant.character.Parent then
		occupant.character.PrimaryPart = occupant.primaryPart
	end
	if root.Parent == occupant.character then
		if occupant.rootPriority ~= nil then root.RootPriority = occupant.rootPriority end
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

local function placeOccupant(state, occupant)
	local character, humanoid, root = occupant.character, occupant.humanoid, occupant.root
	if not root or not root.Parent then return end
	-- Snapshot hat offsets before the head moves. Teleporting a limb apart
	-- from its accessory makes the humanoid drop the handle.
	rememberAccessories(occupant, true)
	local target = upright(captureCFrame(state, humanoid, root))
	if rigIsR6(character, humanoid) then
		-- Keep the HumanoidRootPart as the assembly root, then move the whole
		-- model. Writing each limb's CFrame on R6 is redirected at the root, so
		-- the torso stays at the grapple spot and only the invisible root arrives.
		if occupant.rootPriority == nil then occupant.rootPriority = root.RootPriority end
		root.RootPriority = 127
		if not occupant.savedPrimary then
			occupant.savedPrimary = true
			occupant.primaryPart = character.PrimaryPart
		end
		character.PrimaryPart = root
		collectPoseJoints(character, occupant.kinematic)
		for _, joint in ipairs(character:GetDescendants()) do
			if joint:IsA("Motor6D") and isOwnedByCharacter(joint.Part0, character)
				and isOwnedByCharacter(joint.Part1, character) then
				joint.Enabled = true
			elseif joint.Name == "RagdollRootWeld" and joint:IsA("Weld") then
				joint.Enabled = false
			end
		end
		rememberAccessories(occupant, false)
		applyAccessories(occupant)
		if typeof(target) == "CFrame" and character.PivotTo then
			character:PivotTo(target)
		else
			root.CFrame = target
		end
		return
	end
	local before = root.CFrame
	if typeof(target) == "CFrame" and typeof(before) == "CFrame" then
		local delta = target * before:Inverse()
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part ~= root and typeof(part.CFrame) == "CFrame" then
				part.CFrame = delta * part.CFrame
			end
		end
	end
	root.CFrame = target
	straightenPose(occupant)
	rememberAccessories(occupant, false)
	applyAccessories(occupant)
end

local function capture(state, owner, character, humanoid)
	if state.occupant or occupiedCharacters[character] then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root.Anchored then return end

	local occupant = {
		player = Players:GetPlayerFromCharacter(character), character = character, humanoid = humanoid, root = root,
		walkSpeed = humanoid.WalkSpeed, autoRotate = humanoid.AutoRotate,
		useJumpPower = humanoid.UseJumpPower, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight,
		rootAnchored = root.Anchored, anchoredParts = {}, bodyColors = {}, animationScripts = {}, kinematic = {},
		connections = {}, detachedTools = {}, accessories = {}, disabledConstraints = {}, handleProps = {},
		breakJointsOnDeath = humanoid.BreakJointsOnDeath,
		requiresNeck = humanoid.RequiresNeck, scalingEnabled = humanoid.AutomaticScalingEnabled,
		captorId = owner.UserId,
		nextDamageAt = os.clock() + 1,
	}
	state.occupant = occupant
	occupiedCharacters[character] = state
	humanoid:SetAttribute("CapsuleLocked", true)
	-- Captivity replaces the old ragdoll session. Rescue must restore a
	-- standing rig, not resume a manual toggle or pending recovery request.
	humanoid:SetAttribute("ManualRagdoll", nil)
	humanoid:SetAttribute("RagdollRecoveryRequested", nil)
	humanoid.BreakJointsOnDeath = false
	-- Scaling rebuilds the rig when parts are anchored and pops hats off R6 and R15.
	humanoid.RequiresNeck = false
	humanoid.AutomaticScalingEnabled = false
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
		finishOccupantDeath(state, occupant)
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
	local function claimServer(part)
		if not part:IsA("BasePart") then return end
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		if part.Anchored then return end
		pcall(function()
			if part:CanSetNetworkOwnership() then part:SetNetworkOwner(nil) end
		end)
	end
	local function holdStill()
		if humanoid.Health <= 0 then return end
		humanoid.AutoRotate = false
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.AutomaticScalingEnabled = false
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
		end
	end
	local function placeUpright()
		placeOccupant(state, occupant)
	end
	local function settle()
		if state.occupant ~= occupant or not root.Parent or humanoid.Health <= 0 then return end
		-- Keep the server as the simulator even if a ragdoll refresh runs before
		-- the parts are anchored. The grappler's copy is the tilted one.
		humanoid:SetAttribute("PhysicsServerUntil", os.clock() + 1e9)
		humanoid:SetAttribute("ForcedRagdollUntil", nil)
		humanoid:SetAttribute("FallRagdollUntil", nil)
		humanoid:SetAttribute("BombRagdollUntil", nil)
		-- Set refuses to stand anyone still grapple-locked, and that refusal
		-- puts the ragdoll tag back. Clear it before recovering.
		humanoid:SetAttribute("GrapplePhysicsLocked", nil)
		for _, part in ipairs(character:GetDescendants()) do claimServer(part) end
		humanoid:RemoveTag("Ragdoll")
		-- Preserve motion so recovery does not play a get-up or move them.
		-- Remember the standing state it restores, then lock that state off.
		Ragdoll.Set(humanoid, false, true)
		if occupant.evaluateStateMachine == nil then
			occupant.evaluateStateMachine = humanoid.EvaluateStateMachine
			occupant.platformStand = humanoid.PlatformStand
			occupant.gettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		end
		holdStill()
		placeUpright()
		freezePose(occupant)
		-- Anchor after the bind pose, then write it again. An in-flight client
		-- packet can still be the ragdoll tilt until the server owns the parts.
		placeUpright()
	end
	settle()
	-- The grapple handoff runs just after release. Pose again once it has finished.
	task.delay(math.max(0.3, (Config.playerOwnershipReleaseDelay or 0.2) + 0.1), settle)
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
			if occupant.poseFrozen then
				freezePose(occupant)
				if occupant.humanoid.Health > 0 and occupant.root.Parent then
					occupant.humanoid.AutoRotate = false
					occupant.humanoid.EvaluateStateMachine = false
					occupant.humanoid.PlatformStand = true
					occupant.humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
					if occupant.humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
						occupant.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
					end
					occupant.humanoid.BreakJointsOnDeath = false
					occupant.humanoid.RequiresNeck = false
					occupant.humanoid.AutomaticScalingEnabled = false
					placeOccupant(state, occupant)
				else
					applyAccessories(occupant)
				end
			end
			if not occupant.character:IsDescendantOf(Workspace) then
				if occupant.waitingForRespawn and occupant.player and occupant.player.Parent == Players then continue end
				restoreCharacter(state, false)
			elseif occupant.humanoid.Health <= 0 then
				finishOccupantDeath(state, occupant)
			elseif os.clock() >= occupant.nextDamageAt then
				occupant.nextDamageAt = os.clock() + 1
				local before = occupant.humanoid.Health
				local amount = Config.capsuleDamagePerSecond or 5
				if before > 0 and before - amount <= 0 then markFreeze(occupant) end
				occupant.humanoid:TakeDamage(amount)
				-- TakeDamage is ignored while the state machine is off. NPCs then
				-- never reach 0, so they never respawn.
				if occupant.humanoid.Health >= before and before > 0 then
					occupant.humanoid.Health = math.max(0, before - amount)
				end
				if state.occupant == occupant and occupant.humanoid.Health <= 0 then
					finishOccupantDeath(state, occupant)
				end
			end
			local animator = occupant.humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
			end
			if state.occupant == occupant then updateHealth(occupant) end
		end
	end
end)


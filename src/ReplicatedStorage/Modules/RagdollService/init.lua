-- Supports classic Motor6D and upgraded AnimationConstraint avatar joints.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Service = {}
local rigs = setmetatable({}, {__mode = "k"})

-- A ragdoll can settle by fractions of a stud for several seconds. Keep the
-- camera still through that movement; only follow a meaningful displacement.
local CAMERA_DEADZONE = 0.75
local CAMERA_FOLLOW_SPEED = 12
local CAMERA_MAX_LAG = 1.25 -- Studs; fast falls must not outrun the camera subject
local OWNERSHIP_CHECK_INTERVAL = 0.25
local SETTLING_FRICTION = 5
local SOCKET_PROPERTIES = {"MaxFrictionTorque", "LimitsEnabled", "TwistLimitsEnabled", "UpperAngle", "TwistLowerAngle", "TwistUpperAngle", "Restitution"}

local function attachmentBody(attachment, character)
	-- Native joint attachments may be nested inside other Attachments/Bones.
	local parent = attachment and attachment.Parent
	while parent and parent ~= character do
		if parent:IsA("BasePart") then return parent.Parent == character and parent or nil end
		parent = parent.Parent
	end
	return nil
end

local function configureSocket(joint)
	local socket = joint.socket
	joint.originalSocketProperties = {}
	for _, property in ipairs(SOCKET_PROPERTIES) do joint.originalSocketProperties[property] = socket[property] end
	local name = string.lower(joint.motor.Name)
	local tilt, twist = 75, 40
	if string.find(name, "neck") then tilt, twist = 40, 45
	elseif string.find(name, "waist") then tilt, twist = 25, 30
	elseif string.find(name, "shoulder") then tilt, twist = 95, 70
	elseif string.find(name, "hip") then tilt, twist = 60, 35
	elseif string.find(name, "elbow") or string.find(name, "knee") then tilt, twist = 80, 10
	elseif string.find(name, "wrist") then tilt, twist = 35, 25
	elseif string.find(name, "ankle") then tilt, twist = 30, 20 end
	socket.LimitsEnabled, socket.TwistLimitsEnabled = true, true
	socket.UpperAngle, socket.TwistLowerAngle, socket.TwistUpperAngle = tilt, -twist, twist
	socket.Restitution, socket.MaxFrictionTorque = 0, SETTLING_FRICTION
end

function Service.RefreshSelfCollisions(humanoid)
	local rig = rigs[humanoid]
	if not rig or not rig.active then return end
	local character = humanoid.Parent
	local adjacent = {}
	local function connect(a, b)
		if not a or not b then return end
		adjacent[a] = adjacent[a] or {}
		adjacent[b] = adjacent[b] or {}
		adjacent[a][b], adjacent[b][a] = true, true
	end
	for _, joint in ipairs(rig.joints) do
		connect(attachmentBody(joint.socket.Attachment0, character), attachmentBody(joint.socket.Attachment1, character))
	end
	for _, entry in ipairs(rig.roots) do connect(entry.weld.Part0, entry.weld.Part1) end
	for _, constraint in ipairs(character:GetDescendants()) do
		if not constraint:IsA("NoCollisionConstraint") then continue end
		local a, b = constraint.Part0, constraint.Part1
		if not a or not b or a.Parent ~= character or b.Parent ~= character then continue end
		if rig.collisionRestore[constraint] == nil then rig.collisionRestore[constraint] = constraint.Enabled end
		-- Leave joint neighbors and the invisible root exempt. Non-neighboring
		-- limbs/torso parts collide, so a folded limb cannot pass through the body.
		constraint.Enabled = a.Name == "HumanoidRootPart" or b.Name == "HumanoidRootPart"
			or (adjacent[a] ~= nil and adjacent[a][b] == true)
	end
end

function Service.RefreshJointFriction(humanoid)
	local rig = rigs[humanoid]
	if not rig or not rig.active then return end
	-- Native avatar friction is strong enough to preserve the standing pose in
	-- free fall. Blast ragdolls need free joints; other ragdolls keep light damping.
	local friction = os.clock() < (humanoid:GetAttribute("BombRagdollUntil") or 0) and 0 or SETTLING_FRICTION
	for _, joint in ipairs(rig.joints) do
		if joint.socket.Parent and joint.socket.MaxFrictionTorque ~= friction then
			joint.socket.MaxFrictionTorque = friction
		end
	end
	if rig.suppressExtraSockets then rig.suppressExtraSockets() end
end

-- Inspect the real engine rig rather than inferring it from the ragdoll tag.
-- This is read-only and does not change ownership, animation, or physics.
function Service.ReportBombRig(humanoid, phase)
	local character = humanoid.Parent
	if not character then return end
	local motors, enabledMotors, animations, enabledAnimations, sockets, assemblies = 0, 0, 0, 0, 0, {}
	local details = {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and item.Parent == character then
			assemblies[item.AssemblyRootPart or item] = true
			if item.Anchored then table.insert(details, "ANCHORED=" .. item.Name) end
		elseif item:IsA("Motor6D") or item:IsA("AnimationConstraint") then
			local upgraded = item:IsA("AnimationConstraint")
			local p0 = upgraded and item.Attachment0 and item.Attachment0.Parent or (not upgraded and item.Part0)
			local p1 = upgraded and item.Attachment1 and item.Attachment1.Parent or (not upgraded and item.Part1)
			if p0 and p1 and p0.Parent == character and p1.Parent == character then
				if upgraded then
					animations += 1
					if item.Enabled then enabledAnimations += 1 end
				else
					motors += 1
					if item.Enabled then enabledMotors += 1 end
				end
				table.insert(details, item.Name .. ":" .. tostring(item.Enabled)
					.. (upgraded and ("/kinematic=" .. tostring(item.IsKinematic)) or ""))
			end
		elseif item:IsA("BallSocketConstraint") and item.Enabled then
			sockets += 1
			table.insert(details, item.Name .. "/friction=" .. tostring(item.MaxFrictionTorque))
		elseif (item:IsA("Weld") or item:IsA("WeldConstraint")) and item.Enabled
			and item.Part0 and item.Part1 and item.Part0.Parent == character and item.Part1.Parent == character then
			table.insert(details, "WELD=" .. item.Name .. ":" .. item.Part0.Name .. "->" .. item.Part1.Name)
		end
	end
	local count = 0
	for _ in pairs(assemblies) do count += 1 end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local tracks = animator and #animator:GetPlayingAnimationTracks() or 0
	local root = character:FindFirstChild("HumanoidRootPart")
	local side = RunService:IsServer() and "SERVER" or ("CLIENT " .. tostring(Players.LocalPlayer and Players.LocalPlayer.Name))
	warn(string.format("[BombRagdoll] %s %s %s ragdolled=%s state=%s evaluate=%s motors=%d/%d animationJoints=%d/%d sockets=%d assemblies=%d tracks=%d speed=%.1f spin=%.1f | %s",
		side, character.Name, phase, tostring(humanoid:GetAttribute("Ragdolled")), tostring(humanoid:GetState()),
		tostring(humanoid.EvaluateStateMachine), enabledMotors, motors, enabledAnimations, animations, sockets, count, tracks,
		root and root.AssemblyLinearVelocity.Magnitude or 0, root and root.AssemblyAngularVelocity.Magnitude or 0, table.concat(details, ", ")))
end

-- Ownership must be checked again after the engine rebuilds assemblies from
-- disabled motors. A one-time assignment can miss the newly separate limbs.
function Service.RefreshOwnership(humanoid)
	local character = humanoid.Parent
	if not character then return false end
	local owner
	if os.clock() >= (humanoid:GetAttribute("PhysicsServerUntil") or 0) then
		local ownerId = humanoid:GetAttribute("GrapplePhysicsOwner")
		if ownerId ~= nil then
			owner = Players:GetPlayerByUserId(ownerId)
		else
			owner = Players:GetPlayerFromCharacter(character)
		end
	end
	local seen, rootAssigned, repairs, unassigned = {}, false, 0, 0
	local root = character:FindFirstChild("HumanoidRootPart")
	for _, part in ipairs(character:GetDescendants()) do
		if not part:IsA("BasePart") then continue end
		local assembly = part.AssemblyRootPart or part
		if seen[assembly] then continue end
		seen[assembly] = true
		local ok, assigned = pcall(function()
			if not assembly:CanSetNetworkOwnership() then return false end
			if assembly:GetNetworkOwnershipAuto() or assembly:GetNetworkOwner() ~= owner then
				assembly:SetNetworkOwner(owner)
				repairs += 1
			end
			return true
		end)
		if not ok or not assigned then unassigned += 1 end
		if root and assembly == (root.AssemblyRootPart or root) then rootAssigned = ok and assigned end
	end
	-- Inspect these on the server when diagnosing a Studio ownership mismatch.
	humanoid:SetAttribute("RagdollExpectedOwner", owner and owner.UserId or 0)
	humanoid:SetAttribute("RagdollOwnershipUnassigned", unassigned)
	if repairs > 0 then
		humanoid:SetAttribute("RagdollOwnershipRepairs", (humanoid:GetAttribute("RagdollOwnershipRepairs") or 0) + repairs)
	end
	return rootAssigned
end

if RunService:IsServer() then
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for humanoid, rig in pairs(rigs) do
			if rig.active and humanoid.Parent and now >= (rig.nextOwnershipCheck or 0) then
				rig.nextOwnershipCheck = now + OWNERSHIP_CHECK_INTERVAL
				Service.RefreshOwnership(humanoid)
				Service.RefreshJointFriction(humanoid)
				Service.RefreshSelfCollisions(humanoid)
			end
		end
	end)
end

function Service.RecoverPose(humanoid)
	local character = humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root.Anchored then return end

	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit

	local position = root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local floor = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	if floor then
		local standingHeight = math.max(2.5, humanoid.HipHeight + root.Size.Y / 2)
		position = Vector3.new(position.X, floor.Position.Y + standingHeight, position.Z)
	else
		position += Vector3.new(0, 1, 0)
	end

	root.AssemblyAngularVelocity = Vector3.zero
	root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	root.CFrame = CFrame.lookAt(position, position + flatLook)
end

local function enableJointRagdoll(joint)
	local motor, socket = joint.motor, joint.socket
	joint.wasEnabled = motor.Enabled
	joint.socketWasEnabled = socket.Enabled
	if joint.native then
		joint.originalFriction = socket.MaxFrictionTorque
	end
	configureSocket(joint)
	motor:SetAttribute("GrappleRestoreEnabled", motor.Enabled)
	socket:SetAttribute("GrappleRagdollSocket", true)
	socket:SetAttribute("GrappleRestoreEnabled", socket.Enabled)
	if joint.a0 and motor:IsA("Motor6D") then
		-- Transform is animated locally and is not replicated. Keep the physical
		-- attachment frames identical on the server and every client.
		joint.a0.CFrame = motor.C0
		joint.a1.CFrame = motor.C1
	end
	motor.Enabled = false
	socket.Enabled = true
end

function Service.Prepare(humanoid)
	if rigs[humanoid] then
		rigs[humanoid].scan()
		return rigs[humanoid]
	end
	local character = humanoid.Parent
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	local rig = {joints = {}, roots = {}, parts = {}, extraSockets = {}, collisionRestore = {}, active = false}
	rigs[humanoid] = rig
	local folder = Instance.new("Folder")
	folder.Name = "GrappleRagdollJoints"
	folder.Parent = character
	-- Normal animated poses suppress self-collision. Ragdoll enables collisions
	-- between non-neighboring parts; the original pair filters return on recovery.
	local selfCollisions = Instance.new("Folder")
	selfCollisions.Name = "GrappleSelfCollision"
	selfCollisions.Parent = character
	local bodyParts = {}
	rig.suppressExtraSockets = function()
		local selected = {}
		for _, joint in ipairs(rig.joints) do selected[joint.socket] = true end
		for _, socket in ipairs(character:GetDescendants()) do
			if socket:IsA("BallSocketConstraint") and not selected[socket]
				and attachmentBody(socket.Attachment0, character) and attachmentBody(socket.Attachment1, character) then
				-- Any unselected body socket is a second physical restriction,
				-- including native sockets our joint matching cannot identify.
				if rig.extraSockets[socket] == nil then rig.extraSockets[socket] = socket.Enabled end
				socket.Enabled = false
			end
		end
	end
	local function findNativeSocket(part0, part1)
		for _, constraint in ipairs(character:GetDescendants()) do
			if constraint:IsA("BallSocketConstraint") and not constraint:IsDescendantOf(folder) then
				local a0, a1 = constraint.Attachment0, constraint.Attachment1
				-- Avatar shoulders can use different attachment objects for their
				-- animation and socket constraints. Match the connected body parts.
				local body0, body1 = attachmentBody(a0, character), attachmentBody(a1, character)
				if body0 and body1 and ((body0 == part0 and body1 == part1)
					or (body0 == part1 and body1 == part0)) then return constraint end
			end
		end
	end
	local function adoptNativeSocket(joint, socket)
		local oldSocket, a0, a1 = joint.socket, joint.a0, joint.a1
		joint.socket, joint.native, joint.a0, joint.a1 = socket, true, nil, nil
		if rig.active then
			-- Preserve the motor's pre-ragdoll state; do not snapshot it again.
			if rig.extraSockets[socket] ~= nil then
				socket.Enabled = rig.extraSockets[socket]
				rig.extraSockets[socket] = nil
			end
			joint.socketWasEnabled, joint.originalFriction = socket.Enabled, socket.MaxFrictionTorque
			configureSocket(joint)
			socket:SetAttribute("GrappleRagdollSocket", true)
			socket:SetAttribute("GrappleRestoreEnabled", socket.Enabled)
			socket.Enabled = true
		end
		oldSocket:Destroy()
		if a0 then a0:Destroy() end
		if a1 then a1:Destroy() end
		Service.RefreshJointFriction(humanoid)
		rig.nextOwnershipCheck = 0
	end
	local function ignoreSelfCollision(part)
		if part.Parent ~= character or bodyParts[part] then return end
		for other in pairs(bodyParts) do
			if other.Parent == character then
				local ignore = Instance.new("NoCollisionConstraint")
				ignore.Name = part.Name .. "_" .. other.Name
				ignore.Part0, ignore.Part1 = part, other
				ignore.Parent = selfCollisions
			end
		end
		bodyParts[part] = true
	end
	local function add(motor)
		if motor:IsA("BasePart") then ignoreSelfCollision(motor) return end
		local upgraded = motor:IsA("AnimationConstraint")
		if not motor:IsA("Motor6D") and not upgraded then return end
		local part0, part1
		if upgraded then
			part0 = motor.Attachment0 and motor.Attachment0.Parent
			part1 = motor.Attachment1 and motor.Attachment1.Parent
		else
			part0, part1 = motor.Part0, motor.Part1
		end
		if not part0 or not part1 or part0.Parent ~= character or part1.Parent ~= character then return end
		if part0.Name == "HumanoidRootPart" or part1.Name == "HumanoidRootPart" then
			for _, entry in ipairs(rig.roots) do if entry.motor == motor then return end end
			-- An enabled root Motor6D/AnimationConstraint can keep animating the
			-- torso relative to the replicated HRP, even with passive limb joints.
			local weld = Instance.new("Weld")
			weld.Name = "RagdollRootWeld"
			weld.Part0, weld.Part1 = part0, part1
			weld.C0 = upgraded and motor.Attachment0.CFrame or motor.C0
			weld.C1 = upgraded and motor.Attachment1.CFrame or motor.C1
			weld.Enabled = false
			weld.Parent = folder
			local entry = {motor = motor, weld = weld}
			table.insert(rig.roots, entry)
			if rig.active then
				entry.wasEnabled = motor.Enabled
				motor.Enabled, weld.Enabled = false, true
				rig.nextOwnershipCheck = 0
			end
			return
		end
		for _, joint in ipairs(rig.joints) do
			if joint.motor == motor then
				if upgraded and not joint.native then
					local native = findNativeSocket(part0, part1)
					if native then adoptNativeSocket(joint, native) end
				end
				return
			end
		end
		if upgraded then
			-- Upgraded avatars already supply the passive joint. Reuse it so we
			-- don't stack competing sockets or edit animation retargeting attachments.
			local constraint = findNativeSocket(part0, part1)
			if constraint then
				local joint = {motor = motor, socket = constraint, native = true, wasEnabled = motor.Enabled}
				table.insert(rig.joints, joint)
				motor:SetAttribute("GrappleRagdollJoint", true)
				if rig.active then
					if rig.extraSockets[constraint] ~= nil then
						constraint.Enabled = rig.extraSockets[constraint]
						rig.extraSockets[constraint] = nil
					end
					enableJointRagdoll(joint)
					Service.RefreshJointFriction(humanoid)
					rig.nextOwnershipCheck = 0
				end
				return
			end
		end
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "Ragdoll_" .. motor.Name, "Ragdoll_" .. motor.Name
		a0.CFrame = upgraded and motor.Attachment0.CFrame or motor.C0
		a1.CFrame = upgraded and motor.Attachment1.CFrame or motor.C1
		a0.Parent, a1.Parent = part0, part1
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = motor.Name
		socket.Attachment0, socket.Attachment1 = a0, a1
		socket.LimitsEnabled, socket.TwistLimitsEnabled = true, true
		socket.UpperAngle = string.find(string.lower(motor.Name), "neck") and 50 or 110
		socket.TwistLowerAngle, socket.TwistUpperAngle = -60, 60
		socket.MaxFrictionTorque, socket.Restitution = 5, 0
		socket.Enabled = false
		socket.Parent = folder
		motor:SetAttribute("GrappleRagdollJoint", true)
		local joint = {motor = motor, socket = socket, a0 = a0, a1 = a1, wasEnabled = motor.Enabled}
		table.insert(rig.joints, joint)
		if rig.active then
			enableJointRagdoll(joint)
			Service.RefreshJointFriction(humanoid)
			rig.nextOwnershipCheck = 0
		end
	end
	rig.scan = function()
		for _, instance in ipairs(character:GetDescendants()) do add(instance) end
	end
	rig.scan()
	local watchedInstances = setmetatable({}, {__mode = "k"})
	local function watch(instance)
		if watchedInstances[instance] then return end
		watchedInstances[instance] = true
		add(instance)
		if instance:IsA("BallSocketConstraint") and not instance:IsDescendantOf(folder) then
			rig.scan()
			local function reconcileSockets()
				rig.scan()
				Service.RefreshJointFriction(humanoid)
			end
			instance:GetPropertyChangedSignal("Attachment0"):Connect(reconcileSockets)
			instance:GetPropertyChangedSignal("Attachment1"):Connect(reconcileSockets)
			Service.RefreshJointFriction(humanoid)
		end
		if instance:IsA("Motor6D") or instance:IsA("AnimationConstraint") then
			local upgraded = instance:IsA("AnimationConstraint")
			instance:GetPropertyChangedSignal(upgraded and "Attachment0" or "Part0"):Connect(function() add(instance) end)
			instance:GetPropertyChangedSignal(upgraded and "Attachment1" or "Part1"):Connect(function() add(instance) end)
		end
		if instance:IsA("NoCollisionConstraint") then
			local function refresh() Service.RefreshSelfCollisions(humanoid) end
			instance:GetPropertyChangedSignal("Part0"):Connect(refresh)
			instance:GetPropertyChangedSignal("Part1"):Connect(refresh)
		end
		Service.RefreshSelfCollisions(humanoid)
	end
	character.DescendantAdded:Connect(watch)
	for _, instance in ipairs(character:GetDescendants()) do watch(instance) end
	humanoid:GetAttributeChangedSignal("BombRagdollUntil"):Connect(function()
		Service.RefreshJointFriction(humanoid)
	end)
	return rig
end

function Service.Set(humanoid, enabled, preserveMotion)
	-- All recovery paths (including grapple escape/tag removal) honor blast stun.
	if not enabled and (humanoid:GetAttribute("GrapplePhysicsLocked")
		or os.clock() < (humanoid:GetAttribute("BombRagdollUntil") or 0)) then
		humanoid:AddTag("Ragdoll")
		return
	end
	local rig = Service.Prepare(humanoid)
	local grappleLocked = humanoid:GetAttribute("GrapplePhysicsLocked") == true
	if enabled and grappleLocked then
		humanoid:UnequipTools()
	end
	if rig.active == enabled then
		Service.RefreshJointFriction(humanoid)
		Service.RefreshSelfCollisions(humanoid)
		humanoid.PlatformStand = enabled and grappleLocked or rig.platformStand == true
		return
	end
	rig.active = enabled
	rig.nextOwnershipCheck = 0
	if enabled then
		rig.autoRotate, rig.platformStand = humanoid.AutoRotate, humanoid.PlatformStand
		rig.stateMachine = humanoid.EvaluateStateMachine
		humanoid:SetAttribute("RagdollRestoreStateMachine", rig.stateMachine)
		rig.gettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		for _, part in ipairs(humanoid.Parent:GetChildren()) do
			if part:IsA("BasePart") then
				rig.parts[part] = {collide = part.CanCollide, properties = part.CustomPhysicalProperties, group = part.CollisionGroup,
					massless = part.Massless, rootPriority = part.RootPriority}
				part.Massless = false
				part.RootPriority = part.Name == "HumanoidRootPart" and 127 or math.min(part.RootPriority, 126)
				part.CollisionGroup = "GrappleCharacters"
				-- A living ragdoll keeps its invisible root non-colliding so it
				-- cannot drag the body around. Once dead, the camera still follows
				-- that root, so it must collide with the floor instead of falling
				-- through it independently of the visible corpse.
				part.CanCollide = part.Name ~= "HumanoidRootPart" or humanoid.Health <= 0
				if part.Name ~= "HumanoidRootPart" then
					local p = part.CurrentPhysicalProperties
					part.CustomPhysicalProperties = PhysicalProperties.new(p.Density, 0.25, 0, 100, 100)
				end
			end
		end
	end
	for _, entry in ipairs(rig.roots) do
		if entry.motor.Parent then
			if enabled then entry.wasEnabled = entry.motor.Enabled end
			entry.motor.Enabled = not enabled and entry.wasEnabled
			entry.weld.Enabled = enabled
		end
	end
	for _, joint in ipairs(rig.joints) do
		if joint.motor.Parent then
			if enabled then
				enableJointRagdoll(joint)
			else
				joint.socket.Enabled = joint.socketWasEnabled == true
				for property, value in pairs(joint.originalSocketProperties or {}) do joint.socket[property] = value end
				joint.motor.Enabled = joint.wasEnabled
			end
		end
	end
	if not enabled then
		for constraint, previousEnabled in pairs(rig.collisionRestore) do
			if constraint.Parent then constraint.Enabled = previousEnabled end
		end
		table.clear(rig.collisionRestore)
		for socket, previousEnabled in pairs(rig.extraSockets) do
			if socket.Parent then socket.Enabled = previousEnabled end
		end
		table.clear(rig.extraSockets)
		for part, previous in pairs(rig.parts) do
			if part.Parent then
				part.CanCollide = previous.collide
				part.CustomPhysicalProperties = previous.properties
				part.CollisionGroup = previous.group
				part.Massless, part.RootPriority = previous.massless, previous.rootPriority
			end
		end
		table.clear(rig.parts)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, rig.gettingUp)
		humanoid:SetAttribute("RagdollRecoveredAt", os.clock())
	end
	if enabled then humanoid.AutoRotate = false else humanoid.AutoRotate = rig.autoRotate end
	humanoid.EvaluateStateMachine = not enabled and rig.stateMachine
	humanoid.PlatformStand = enabled and grappleLocked or rig.platformStand == true
	humanoid:SetAttribute("Ragdolled", enabled)
	Service.RefreshJointFriction(humanoid)
	Service.RefreshSelfCollisions(humanoid)
	if humanoid.Health > 0 then
		humanoid:ChangeState(enabled and Enum.HumanoidStateType.Physics or Enum.HumanoidStateType.GettingUp)
	end
	if not enabled and humanoid.Health > 0 and not preserveMotion then Service.RecoverPose(humanoid) end
	if enabled then Service.RefreshOwnership(humanoid) end
end

function Service.InitClient()
	if RunService:IsServer() or Service.clientStarted then return end
	Service.clientStarted = true
	local localPlayer = Players.LocalPlayer
	local cameraAnchor: Part?
	local cameraRoot: BasePart?
	local cameraHumanoid: Humanoid?
	if localPlayer then
		localPlayer.CharacterAdded:Connect(function(character)
			cameraRoot, cameraHumanoid = nil, nil
			local camera = workspace.CurrentCamera
			if cameraAnchor and camera and camera.CameraSubject == cameraAnchor then
				camera.CameraSubject = character:WaitForChild("Humanoid")
			end
		end)
	end

	local function updateCameraSubject(humanoid: Humanoid, enabled: boolean)
		if not localPlayer or humanoid.Parent ~= localPlayer.Character then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		if not enabled then
			cameraRoot, cameraHumanoid = nil, nil
			if cameraAnchor and camera.CameraSubject == cameraAnchor then camera.CameraSubject = humanoid end
			return
		end

		local root = humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then return end
		if not cameraAnchor then
			cameraAnchor = Instance.new("Part")
			cameraAnchor.Name = "RagdollCameraAnchor"
			cameraAnchor.Anchored = true
			cameraAnchor.CanCollide = false
			cameraAnchor.CanQuery = false
			cameraAnchor.CanTouch = false
			cameraAnchor.Transparency = 1
			cameraAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
			cameraAnchor.Parent = workspace
		end
		cameraAnchor.CFrame = CFrame.new(root.Position)
		cameraRoot, cameraHumanoid = root, humanoid
		camera.CameraSubject = cameraAnchor
	end
	-- Ownership can move to another player. Every client must configure all
	-- ragdolls it sees, including the victim the local player is now simulating.
	local watched = setmetatable({}, {__mode = "k"})
	local activeRigs = {}
	local pendingEntryMotion = {}
	local function startAirborneMotion(humanoid)
		if humanoid.Parent ~= localPlayer.Character or humanoid.Health <= 0
			or humanoid:GetAttribute("GrapplePhysicsLocked") or humanoid:GetAttribute("GrappleLocalPhysicsLock")
			or humanoid:GetAttribute("BombRagdollUntil") ~= nil then return true end
		-- Only the local simulator may seed this motion. Observers never write
		-- velocities, and bomb/grapple ownership transitions use their own launch.
		if humanoid:GetAttribute("RagdollExpectedOwner") ~= localPlayer.UserId then return false end
		local root = humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if not root or root.Anchored then return true end
		local velocity = root.AssemblyLinearVelocity
		if math.abs(velocity.Y) < 5 or root.AssemblyAngularVelocity.Magnitude > 1.5 then return true end
		local assemblies, count = {}, 0
		for _, part in ipairs(humanoid.Parent:GetChildren()) do
			if part:IsA("BasePart") then
				local assembly = part.AssemblyRootPart or part
				if not assemblies[assembly] then assemblies[assembly] = true count += 1 end
			end
		end
		if count < 2 then return false end -- Wait for the replicated motors to split.
		local axis = Vector3.new(velocity.Z, 0, -velocity.X)
		if axis.Magnitude < 0.01 then
			local look = root.CFrame.LookVector
			axis = Vector3.new(look.Z, 0, -look.X)
		end
		if axis.Magnitude < 0.01 then axis = Vector3.new(1, 0, 0) end
		local rootAssembly = root.AssemblyRootPart or root
		for assembly in pairs(assemblies) do
			if not assembly.Anchored and assembly.AssemblyAngularVelocity.Magnitude < 2 then
				assembly.AssemblyAngularVelocity += axis.Unit * (assembly == rootAssembly and 1.2 or -0.6)
			end
		end
		return true
	end
	local function bind(humanoid)
		if not humanoid:IsA("Humanoid") or watched[humanoid] then return end
		watched[humanoid] = true
		local previousStateMachine = humanoid.EvaluateStateMachine
		local previousGettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		local wasRagdolled, wasLocked = false, false
		local reportedBlast
		local function reportBlast()
			local revision = humanoid:GetAttribute("BombBlastRevision")
			if humanoid:GetAttribute("BombRagdollDebug") ~= true or not revision or reportedBlast == revision then return end
			reportedBlast = revision
			task.delay(0.5, function()
				if humanoid.Parent and humanoid:GetAttribute("BombBlastRevision") == revision then
					Service.ReportBombRig(humanoid, "airborne")
				end
			end)
		end
		humanoid:GetAttributeChangedSignal("BombBlastRevision"):Connect(reportBlast)
		humanoid:GetAttributeChangedSignal("BombRagdollDebug"):Connect(reportBlast)
		reportBlast()
		local function update()
			local ragdolled = humanoid:GetAttribute("Ragdolled") == true
			local locked = humanoid:GetAttribute("GrapplePhysicsLocked") == true
				or humanoid:GetAttribute("GrappleLocalPhysicsLock") == true
			local enabled = ragdolled or locked
			if ragdolled == wasRagdolled and locked == wasLocked then return end
			if ragdolled and not wasRagdolled and localPlayer and humanoid.Parent == localPlayer.Character then
				pendingEntryMotion[humanoid] = os.clock() + 0.5
			elseif not ragdolled or locked then
				pendingEntryMotion[humanoid] = nil
			end
			wasRagdolled, wasLocked = ragdolled, locked
			updateCameraSubject(humanoid, enabled)
			local restoreStateMachine = humanoid:GetAttribute("RagdollRestoreStateMachine")
			if restoreStateMachine == nil then restoreStateMachine = previousStateMachine end
			humanoid.EvaluateStateMachine = not enabled and restoreStateMachine
			-- PlatformStand blocks the native Backpack equip path for free ragdolls.
			humanoid.PlatformStand = locked
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, not enabled and previousGettingUp)
			-- Joint/attachment/collision layout is replicated from the server.
			-- Local rewrites can leave observers using a different assembly graph.
			activeRigs[humanoid] = enabled or nil
			if humanoid.Health > 0 then
				humanoid:ChangeState(enabled and Enum.HumanoidStateType.Physics or Enum.HumanoidStateType.GettingUp)
			end
		end
		humanoid:GetAttributeChangedSignal("Ragdolled"):Connect(update)
		humanoid:GetAttributeChangedSignal("GrapplePhysicsLocked"):Connect(update)
		humanoid:GetAttributeChangedSignal("GrappleLocalPhysicsLock"):Connect(update)
		update()
	end
	workspace.DescendantAdded:Connect(bind)
	for _, instance in ipairs(workspace:GetDescendants()) do bind(instance) end
	RunService:BindToRenderStep("GrappleRagdollCameraAnchor", Enum.RenderPriority.Camera.Value - 1, function(dt)
		if not cameraAnchor or not cameraRoot or not cameraHumanoid or cameraHumanoid.Health <= 0 then return end
		if cameraRoot.Parent == nil or cameraHumanoid.Parent == nil then return end
		local camera = workspace.CurrentCamera
		if camera and camera.CameraSubject ~= cameraAnchor then camera.CameraSubject = cameraAnchor end

		local offset = cameraRoot.Position - cameraAnchor.Position
		if offset.Magnitude <= CAMERA_DEADZONE then return end
		-- Smooth small movements consistently across frame rates, but bound the
		-- remaining distance. Unbounded easing trails fast falls by many studs.
		local remaining = offset * math.exp(-math.max(0, dt) * CAMERA_FOLLOW_SPEED)
		if remaining.Magnitude > CAMERA_MAX_LAG then
			remaining = remaining.Unit * CAMERA_MAX_LAG
		end
		cameraAnchor.CFrame = CFrame.new(cameraRoot.Position - remaining)
	end)
	RunService.PreSimulation:Connect(function()
		for humanoid, deadline in pairs(pendingEntryMotion) do
			if not humanoid.Parent or os.clock() > deadline or startAirborneMotion(humanoid) then
				pendingEntryMotion[humanoid] = nil
			end
		end
		for humanoid in pairs(activeRigs) do
			if not humanoid.Parent then activeRigs[humanoid] = nil continue end
			humanoid.EvaluateStateMachine = false
			humanoid.PlatformStand = humanoid:GetAttribute("GrapplePhysicsLocked") == true
				or humanoid:GetAttribute("GrappleLocalPhysicsLock") == true
			if humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
			-- The separate camera anchor already smooths the view. Do not write
			-- assembly velocities here: observers must consume the owner's physics.
		end
	end)
end
return Service

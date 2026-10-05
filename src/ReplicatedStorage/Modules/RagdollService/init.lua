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
		socket.MaxFrictionTorque = math.max(5, joint.originalFriction)
	end
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
	local rig = {joints = {}, roots = {}, parts = {}, active = false}
	rigs[humanoid] = rig
	local folder = Instance.new("Folder")
	folder.Name = "GrappleRagdollJoints"
	folder.Parent = character
	-- Players can collide with other players. Suppress only pairs inside this
	-- character so overlapping ragdoll limbs cannot push their own body apart.
	local selfCollisions = Instance.new("Folder")
	selfCollisions.Name = "GrappleSelfCollision"
	selfCollisions.Parent = character
	local bodyParts = {}
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
		for _, joint in ipairs(rig.joints) do if joint.motor == motor then return end end
		if upgraded then
			-- Upgraded avatars already supply the passive joint. Reuse it so we
			-- don't stack competing sockets or edit animation retargeting attachments.
			for _, constraint in ipairs(character:GetDescendants()) do
				if constraint:IsA("BallSocketConstraint")
					and constraint.Attachment0 == motor.Attachment0 and constraint.Attachment1 == motor.Attachment1 then
					local joint = {motor = motor, socket = constraint, native = true, wasEnabled = motor.Enabled}
					table.insert(rig.joints, joint)
					motor:SetAttribute("GrappleRagdollJoint", true)
					if rig.active then enableJointRagdoll(joint) rig.nextOwnershipCheck = 0 end
					return
				end
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
		if rig.active then enableJointRagdoll(joint) rig.nextOwnershipCheck = 0 end
	end
	rig.scan = function()
		for _, instance in ipairs(character:GetDescendants()) do add(instance) end
	end
	rig.scan()
	character.DescendantAdded:Connect(function(instance)
		add(instance)
		if instance:IsA("Motor6D") or instance:IsA("AnimationConstraint") then
			local upgraded = instance:IsA("AnimationConstraint")
			instance:GetPropertyChangedSignal(upgraded and "Attachment0" or "Part0"):Connect(function() add(instance) end)
			instance:GetPropertyChangedSignal(upgraded and "Attachment1" or "Part1"):Connect(function() add(instance) end)
		end
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
	if rig.active == enabled then return end
	rig.active = enabled
	rig.nextOwnershipCheck = 0
	if enabled then
		rig.autoRotate, rig.platformStand = humanoid.AutoRotate, humanoid.PlatformStand
		rig.stateMachine = humanoid.EvaluateStateMachine
		humanoid:SetAttribute("RagdollRestoreStateMachine", rig.stateMachine)
		rig.gettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:UnequipTools()
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
				if joint.native then joint.socket.MaxFrictionTorque = joint.originalFriction end
				joint.motor.Enabled = joint.wasEnabled
			end
		end
	end
	if not enabled then
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
	humanoid.PlatformStand = enabled or rig.platformStand == true
	humanoid:SetAttribute("Ragdolled", enabled)
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
	local function bind(humanoid)
		if not humanoid:IsA("Humanoid") or watched[humanoid] then return end
		watched[humanoid] = true
		local previousStateMachine = humanoid.EvaluateStateMachine
		local previousGettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		local wasRagdolled, wasLocked = false, false
		local function update()
			local ragdolled = humanoid:GetAttribute("Ragdolled") == true
			local locked = humanoid:GetAttribute("GrapplePhysicsLocked") == true
				or humanoid:GetAttribute("GrappleLocalPhysicsLock") == true
			local enabled = ragdolled or locked
			if ragdolled == wasRagdolled and locked == wasLocked then return end
			wasRagdolled, wasLocked = ragdolled, locked
			updateCameraSubject(humanoid, enabled)
			local restoreStateMachine = humanoid:GetAttribute("RagdollRestoreStateMachine")
			if restoreStateMachine == nil then restoreStateMachine = previousStateMachine end
			humanoid.EvaluateStateMachine = not enabled and restoreStateMachine
			humanoid.PlatformStand = enabled
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
		for humanoid in pairs(activeRigs) do
			if not humanoid.Parent then activeRigs[humanoid] = nil continue end
			humanoid.EvaluateStateMachine = false
			humanoid.PlatformStand = true
			if humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
			-- The separate camera anchor already smooths the view. Do not write
			-- assembly velocities here: observers must consume the owner's physics.
		end
	end)
end
return Service

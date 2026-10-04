-- Supports classic Motor6D and upgraded AnimationConstraint avatar joints.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Service = {}
local rigs = setmetatable({}, {__mode = "k"})

-- A ragdoll can settle by fractions of a stud for several seconds. Keep the
-- camera still through that movement; only follow a meaningful displacement.
local CAMERA_DEADZONE = 0.75
local CAMERA_FOLLOW_SPEED = 12

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
	motor:SetAttribute("GrappleRestoreEnabled", motor.Enabled)
	socket:SetAttribute("GrappleRagdollSocket", true)
	socket:SetAttribute("GrappleRestoreEnabled", socket.Enabled)
	if joint.a0 and motor:IsA("Motor6D") then
		joint.a0.CFrame = motor.C0 * motor.Transform
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
	local rig = {joints = {}, parts = {}, active = false}
	rigs[humanoid] = rig
	local folder = Instance.new("Folder")
	folder.Name = "GrappleRagdollJoints"
	folder.Parent = character
	local function add(motor)
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
		if part0.Name == "HumanoidRootPart" or part1.Name == "HumanoidRootPart" then return end
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
					if rig.active then enableJointRagdoll(joint) end
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
		socket.MaxFrictionTorque, socket.Restitution = 0, 0
		socket.Enabled = false
		socket.Parent = folder
		motor:SetAttribute("GrappleRagdollJoint", true)
		local joint = {motor = motor, socket = socket, a0 = a0, a1 = a1, wasEnabled = motor.Enabled}
		table.insert(rig.joints, joint)
		if rig.active then enableJointRagdoll(joint) end
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

function Service.Set(humanoid, enabled)
	local rig = Service.Prepare(humanoid)
	if rig.active == enabled then return end
	rig.active = enabled
	if enabled then
		rig.autoRotate, rig.platformStand = humanoid.AutoRotate, humanoid.PlatformStand
		rig.gettingUp = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:UnequipTools()
		for _, part in ipairs(humanoid.Parent:GetChildren()) do
			if part:IsA("BasePart") then
				rig.parts[part] = {collide = part.CanCollide, properties = part.CustomPhysicalProperties, group = part.CollisionGroup}
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
	for _, joint in ipairs(rig.joints) do
		if joint.motor.Parent then
			if enabled then
				enableJointRagdoll(joint)
			else
				joint.socket.Enabled = joint.socketWasEnabled == true
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
			end
		end
		table.clear(rig.parts)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, rig.gettingUp)
		humanoid:SetAttribute("RagdollRecoveredAt", os.clock())
	end
	if enabled then humanoid.AutoRotate = false else humanoid.AutoRotate = rig.autoRotate end
	humanoid.PlatformStand = enabled or rig.platformStand == true
	humanoid:SetAttribute("Ragdolled", enabled)
	if humanoid.Health > 0 then
		humanoid:ChangeState(enabled and Enum.HumanoidStateType.Ragdoll or Enum.HumanoidStateType.GettingUp)
	end
	if not enabled and humanoid.Health > 0 then Service.RecoverPose(humanoid) end
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
		local active = false
		local function update()
			local enabled = humanoid:GetAttribute("Ragdolled") == true
			if enabled == active then return end
			active = enabled
			updateCameraSubject(humanoid, enabled)
			humanoid.EvaluateStateMachine = not enabled and previousStateMachine
			humanoid.PlatformStand = enabled
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, not enabled and previousGettingUp)
			local joints = {}
			for _, joint in ipairs(humanoid.Parent:GetDescendants()) do
				if joint:GetAttribute("GrappleRagdollJoint") or joint:GetAttribute("GrappleRagdollSocket") then
					table.insert(joints, joint)
					if not enabled then joint.Enabled = joint:GetAttribute("GrappleRestoreEnabled") == true end
				end
			end
			activeRigs[humanoid] = enabled and joints or nil
			if enabled then
				for _, part in ipairs(humanoid.Parent:GetChildren()) do
					if part:IsA("BasePart") then
						part.CanCollide = part.Name ~= "HumanoidRootPart" or humanoid.Health <= 0
					end
				end
			end
			if humanoid.Health > 0 then
				humanoid:ChangeState(enabled and Enum.HumanoidStateType.Ragdoll or Enum.HumanoidStateType.GettingUp)
			end
		end
		humanoid:GetAttributeChangedSignal("Ragdolled"):Connect(update)
		if humanoid:GetAttribute("Ragdolled") then update() end
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
		local alpha = math.min(1, dt * CAMERA_FOLLOW_SPEED)
		cameraAnchor.CFrame = CFrame.new(cameraAnchor.Position + offset * alpha)
	end)
	RunService.PreSimulation:Connect(function()
		for humanoid, joints in pairs(activeRigs) do
			if not humanoid.Parent then activeRigs[humanoid] = nil continue end
			humanoid.EvaluateStateMachine = false
			humanoid.PlatformStand = true
			if humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Ragdoll then
				humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
			end
			-- The default camera follows HumanoidRootPart. Let the limbs tumble,
			-- but do not let physics rotate that invisible camera anchor every frame.
			local root = humanoid.Parent:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then root.AssemblyAngularVelocity = Vector3.zero end
			for _, joint in ipairs(joints) do
				if joint.Parent then joint.Enabled = joint:GetAttribute("GrappleRagdollSocket") == true end
			end
		end
	end)
end
return Service

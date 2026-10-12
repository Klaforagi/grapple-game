-- Admin noclip. Z asks the server to toggle the Noclip attribute. Only AdminList
-- can set it. While it is on, the body clips through the world, walk animations
-- stay off, and the mouse turns the character the way shift lock does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Motion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AdminNoclipMotion"))
local Remotes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrappleRemotes"))

local player = Players.LocalPlayer
local SHIFTLOCK_OFFSET = Vector3.new(1.75, 0, 0)
local active = false
local savedCollide = {}
local boundCharacter = nil
-- Owned flight position. Reading the root each frame keeps the drop gravity
-- applied between renders, so the body sinks.
local flightPosition = nil
local animConn, addedConn, heartbeatConn, physicsConn

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = "Noclip", Text = text, Duration = 3})
	end)
end

local function remember(part)
	if savedCollide[part] == nil then savedCollide[part] = part.CanCollide end
	part.CanCollide = false
end

local function clipCharacter(character)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then remember(inst) end
	end
end

local function freezeTracks(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

local function held()
	return {
		w = UserInputService:IsKeyDown(Enum.KeyCode.W),
		a = UserInputService:IsKeyDown(Enum.KeyCode.A),
		s = UserInputService:IsKeyDown(Enum.KeyCode.S),
		d = UserInputService:IsKeyDown(Enum.KeyCode.D),
		up = UserInputService:IsKeyDown(Enum.KeyCode.Space),
		down = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl),
		fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift),
	}
end

local function prepare(character)
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	boundCharacter = character
	clipCharacter(character)
	if humanoid:GetAttribute("ManualRagdoll") then
		Remotes.ToggleRagdoll:FireServer()
	end
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.CameraOffset = SHIFTLOCK_OFFSET
	pcall(function() humanoid.EvaluateStateMachine = false end)
	freezeTracks(humanoid)
	if animConn then animConn:Disconnect() end
	animConn = humanoid.AnimationPlayed:Connect(function(track)
		if active then track:Stop(0) end
	end)
	if addedConn then addedConn:Disconnect() end
	addedConn = character.DescendantAdded:Connect(function(inst)
		if active and inst:IsA("BasePart") then remember(inst) end
	end)
end

local function restoreCharacter()
	local character = boundCharacter
	boundCharacter = nil
	if animConn then animConn:Disconnect() animConn = nil end
	if addedConn then addedConn:Disconnect() addedConn = nil end
	for part, collide in pairs(savedCollide) do
		if part.Parent then part.CanCollide = collide end
	end
	table.clear(savedCollide)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid.CameraOffset = Vector3.zero
		pcall(function() humanoid.EvaluateStateMachine = true end)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function lockMouse()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

local function step(dt)
	if not active then return end
	if UserInputService:GetFocusedTextBox() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		return
	end
	lockMouse()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or humanoid.Health <= 0 then return end
	if boundCharacter ~= character then prepare(character) end
	clipCharacter(character)
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.CameraOffset = SHIFTLOCK_OFFSET
	-- Physics keeps the humanoid from standing the body back onto the floor.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local keys = held()
	if not flightPosition then flightPosition = root.Position end
	local dx, dy, dz = Motion.Direction(keys, look, right)
	local nextPos = Motion.Move(flightPosition, {X = dx, Y = dy, Z = dz}, Motion.SpeedFor(keys.fast), dt)
	flightPosition = Vector3.new(nextPos.X, nextPos.Y, nextPos.Z)
	local yawX, yawZ = Motion.FlatLook(look)
	if not yawX then yawX, yawZ = Motion.FlatLook(root.CFrame.LookVector) end
	if not yawX then yawX, yawZ = 0, -1 end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(Vector3.new(nextPos.X, nextPos.Y, nextPos.Z), Vector3.new(nextPos.X + yawX, nextPos.Y, nextPos.Z + yawZ))
end

local function setActive(on)
	if on == active then return end
	active = on
	if not on then
		RunService:UnbindFromRenderStep("AdminNoclipMouse")
		RunService:UnbindFromRenderStep("AdminNoclipMove")
		if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
		if physicsConn then physicsConn:Disconnect() physicsConn = nil end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		flightPosition = nil
		restoreCharacter()
		notify("Off")
		return
	end
	RunService:BindToRenderStep("AdminNoclipMouse", Enum.RenderPriority.Camera.Value - 1, lockMouse)
	RunService:BindToRenderStep("AdminNoclipMove", Enum.RenderPriority.Camera.Value + 1, step)
	heartbeatConn = RunService.Heartbeat:Connect(function()
		local humanoid = boundCharacter and boundCharacter:FindFirstChildOfClass("Humanoid")
		if active and humanoid then freezeTracks(humanoid) end
	end)
	-- Stepped runs immediately before physics. The humanoid turns limb collision
	-- back on during the step, which shoves the body out of whatever it entered.
	physicsConn = RunService.Stepped:Connect(function()
		local character = player.Character
		if not active or not character then return end
		for _, inst in ipairs(character:GetDescendants()) do
			if inst:IsA("BasePart") then inst.CanCollide = false end
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if flightPosition and root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = CFrame.new(flightPosition) * (root.CFrame - root.CFrame.Position)
		end
	end)
	if player.Character then prepare(player.Character) end
	notify("On. Fly where you look. Shift is faster.")
end

player:GetAttributeChangedSignal("Noclip"):Connect(function()
	setActive(player:GetAttribute("Noclip") == true)
end)
player.CharacterAdded:Connect(function(character)
	flightPosition = nil
	if active then task.defer(prepare, character) end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.Z then return end
	if UserInputService:GetFocusedTextBox() then return end
	if player:GetAttribute("Admin") ~= true then return end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("AdminNoclip")
	if remote then remote:FireServer() end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	folder:WaitForChild("AdminNoclip")
	setActive(player:GetAttribute("Noclip") == true)
end)

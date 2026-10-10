local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local KICK_COOLDOWN = 1
local KICK_SPEED = 40
local KICK_LIFT = 38 / 1.05
local ROLL_DRAG = 0.7 -- Higher values make grounded balls slow down sooner.
local STOP_SPEED = 0.6
local balls = {}

local function tethered(part)
	local assembly = part.AssemblyRootPart or part
	return assembly:GetAttribute("WallGrappleOwner") ~= nil
end

local function playerFromPart(part)
	local ancestor = part.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			if player then return player, ancestor end
		end
		ancestor = ancestor.Parent
	end
end

local function ownAssembly(part)
	if tethered(part) then return end
	if not part.Anchored then
		pcall(function()
			if part:CanSetNetworkOwnership() then part:SetNetworkOwner(nil) end
		end)
	end
end

local function register(model)
	if balls[model] or (not model:IsA("Model") and not model:IsA("BasePart")) or model.Name ~= "SoccerBall"
		or not model:IsDescendantOf(Workspace) then return end
	local kickSound = model:FindFirstChild("Kick", true)
	local ball = model:IsA("BasePart") and model or kickSound and kickSound.Parent:IsA("BasePart") and kickSound.Parent
		or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not ball then return end
	local state = {part = ball, cooldowns = setmetatable({}, {__mode = "k"}), connections = {}, parts = {}}
	balls[model] = state
	local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = {model}
    state.overlap, state.scanAt = overlap, 0
    local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	state.raycast = params
	ownAssembly(ball)
	local function attach(part)
		if not part:IsA("BasePart") or state.parts[part] then return end
		state.parts[part] = true
		part.CanTouch = true
		local function kick(hit)
			if not ball:IsDescendantOf(Workspace) or ball.Anchored or tethered(ball) then return end
			local player, character = playerFromPart(hit)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not player or not humanoid or humanoid.Health <= 0 or not root
				or humanoid:GetAttribute("CapsuleLocked") then return end
			local now = os.clock()
			if now < (state.cooldowns[player] or 0) then return end
			local delta = ball.Position - root.Position
			local direction = Vector3.new(delta.X, 0, delta.Z)
			if direction.Magnitude < 0.01 then
				local look = root.CFrame.LookVector
				direction = Vector3.new(look.X, 0, look.Z)
			end
			if direction.Magnitude < 0.01 then return end
			state.cooldowns[player] = now + KICK_COOLDOWN
			ownAssembly(ball)
			-- One bounded kick, with no lingering BodyVelocity fighting contacts.
			ball.AssemblyLinearVelocity = direction.Unit * KICK_SPEED + Vector3.new(0, KICK_LIFT, 0)
			ball.AssemblyAngularVelocity = Vector3.zero
			local sound = model:FindFirstChild("Kick", true)
			if sound and sound:IsA("Sound") then sound:Play() end
		end
		state.kick = kick
		table.insert(state.connections, part.Touched:Connect(kick))
	end
	attach(model)
	for _, part in ipairs(model:GetDescendants()) do attach(part) end
	table.insert(state.connections, model.DescendantAdded:Connect(attach))
end

Workspace.DescendantAdded:Connect(function(item)
	task.defer(function()
		local ancestor = item
		while ancestor and ancestor ~= Workspace do
			if (ancestor:IsA("Model") or ancestor:IsA("BasePart")) and ancestor.Name == "SoccerBall" then register(ancestor) break end
			ancestor = ancestor.Parent
		end
	end)
end)
for _, item in ipairs(Workspace:GetDescendants()) do register(item) end

RunService.PreSimulation:Connect(function(dt)
	for model, state in pairs(balls) do
		local ball = state.part
		if not model:IsDescendantOf(Workspace) or (ball ~= model and not ball:IsDescendantOf(model)) then
			for _, connection in ipairs(state.connections) do connection:Disconnect() end
			balls[model] = nil
			continue
		end
		-- The grappler simulates a tethered ball. Server kicks and damping would
		-- overwrite that simulation and produce visible corrections/jitter.
		if ball.Anchored or tethered(ball) then continue end
        if os.clock() >= state.scanAt and state.kick then
            state.scanAt = os.clock() + 0.1
            for _, hit in ipairs(Workspace:GetPartsInPart(ball, state.overlap)) do state.kick(hit) end
        end
		local frame, size = ball.CFrame, ball.Size
		local halfHeight = (math.abs(frame.RightVector.Y) * size.X
			+ math.abs(frame.UpVector.Y) * size.Y + math.abs(frame.LookVector.Y) * size.Z) / 2
		local contact = Workspace:Raycast(ball.Position, Vector3.new(0, -halfHeight - 0.15, 0), state.raycast)
		local velocity = ball.AssemblyLinearVelocity
		-- Leave airborne kicks alone. Only apply rolling resistance near ground.
		if not contact or math.abs(velocity.Y) > 2 then continue end
		local surfaceVelocity = contact.Instance:IsA("BasePart")
			and contact.Instance:GetVelocityAtPosition(contact.Position) or Vector3.zero
		local relative = velocity - surfaceVelocity
		local horizontal = Vector3.new(relative.X, 0, relative.Z) * math.exp(-ROLL_DRAG * dt)
		local spin = ball.AssemblyAngularVelocity * math.exp(-ROLL_DRAG * dt)
		if horizontal.Magnitude < STOP_SPEED and contact.Normal.Y > 0.98 then
			horizontal, spin = Vector3.zero, Vector3.zero
		end
		ball.AssemblyLinearVelocity = surfaceVelocity + horizontal + Vector3.new(0, relative.Y, 0)
		ball.AssemblyAngularVelocity = spin
	end
end)

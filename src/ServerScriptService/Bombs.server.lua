local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local BombPhysics = require(Storage.Modules:WaitForChild("BombPhysics"))
local FastCast = require(Storage.Modules:WaitForChild("FastCastRedux"))
local Ragdoll = require(Storage.Modules:WaitForChild("RagdollService"))
local PlaySound = require(Storage.Modules:WaitForChild("PlaySound"))
local lastThrow, liveBombs, coolingTools, pendingLaunches, stunned = {}, {}, {}, {}, {}
local issued = setmetatable({}, {__mode = "k"})
local SERVER_HOLD = 0.3
local bombCaster = FastCast.new()

local bombColors = {
	Black = Color3.fromRGB(20, 20, 20), White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(220, 55, 55), Orange = Color3.fromRGB(242, 143, 43),
	Yellow = Color3.fromRGB(245, 220, 55), Green = Color3.fromRGB(65, 180, 90), Blue = Color3.fromRGB(55, 125, 230), Purple = Color3.fromRGB(145, 82, 210),
	Pink = Color3.fromRGB(240, 105, 175), Cyan = Color3.fromRGB(35, 210, 225), Teal = Color3.fromRGB(35, 155, 145), Lime = Color3.fromRGB(150, 225, 55),
}

local function sphere(name, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(0, 255, 255)
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return part
end

local function hideUntilReady(tool, readyAt)
	local parts = coolingTools[tool] and coolingTools[tool].parts or {}
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			if parts[part] == nil then parts[part] = part.Transparency end
			part.Transparency = 1
		end
	end
	tool.Enabled = false
	tool:SetAttribute("BombCoolingDown", true)
	coolingTools[tool] = {readyAt = readyAt, parts = parts}
end

local function giveBomb(player, character)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then return end
	if not character:FindFirstChild(Config.toolName) then backpack:WaitForChild(Config.toolName, 10) end
	if player.Character ~= character or not character.Parent or issued[character] then return end
	issued[character] = true
	if backpack:FindFirstChild(Config.bombToolName) or character:FindFirstChild(Config.bombToolName) then return end
	local tool = Instance.new("Tool")
	tool.Name = Config.bombToolName
	tool.ToolTip = "Throw a bomb / " .. Config.bombFuse .. " second fuse"
	tool.CanBeDropped = false
	tool:SetAttribute("BombTool", true)
	local handle = sphere("Handle", 1.2, bombColors[player:GetAttribute("BombColor")])
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.Parent = tool
	tool.Parent = backpack
	local readyAt = (lastThrow[player] or -math.huge) + Config.bombCooldown
	if os.clock() < readyAt then hideUntilReady(tool, readyAt) end
end

local function cleanupBomb(bomb, state)
	if state.cleaned then return end
	state.cleaned = true
	liveBombs[bomb] = nil
	if state.cast then
		state.cast:Terminate()
		state.cast = nil
	end
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
end

local function refreshCastFilter(state)
	if state.raycastParams then
		-- FastCast snapshots this property between pierce tests, so assign the
		-- growing table again whenever respawned tools/parts are excluded.
		state.raycastParams.FilterDescendantsInstances = state.filter
	end
end

local function protectThrower(bomb, state, container)
	local function ignore(part)
		if not part:IsA("BasePart") or state.ignored[part] then return end
		state.ignored[part] = true
		table.insert(state.filter, part) -- Still ignore equipment if it is reparented later.
		refreshCastFilter(state)
		local constraint = Instance.new("NoCollisionConstraint")
		constraint.Part0, constraint.Part1 = bomb, part
		constraint.Parent = bomb -- Lasts for the entire fuse, not just the first 0.3 seconds.
	end
	table.insert(state.filter, container)
	refreshCastFilter(state)
	for _, part in ipairs(container:GetDescendants()) do ignore(part) end
	table.insert(state.connections, container.DescendantAdded:Connect(ignore))
end

local function canStick(state, bomb, hit)
	if state.stuck or not bomb.Parent or not hit or not hit.Parent then return false end
	if hit == bomb or hit:IsDescendantOf(bomb) or state.ignored[hit] then return false end
	if hit:IsDescendantOf(state.character)
		or (state.player.Character and hit:IsDescendantOf(state.player.Character)) then return false end
	-- Tools and invisible effect/camera parts are not sticky surfaces.
	if hit:FindFirstAncestorOfClass("Tool") then return false end
	if not hit:IsA("Terrain") then
		if not hit:IsA("BasePart") then return false end
		local model = hit:FindFirstAncestorOfClass("Model")
		if not hit.CanCollide and not (model and model:FindFirstChildOfClass("Humanoid")) then return false end
	end
	return true
end

local function stick(bomb, state, hit, position)
	if not canStick(state, bomb, hit) then return false end
	state.stuck = true
	bomb.AssemblyLinearVelocity, bomb.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	if position then bomb.Position = position end
	bomb.CanCollide, bomb.CanTouch, bomb.Massless = false, false, true
	if hit:IsA("Terrain") then
		bomb.Anchored = true
	else
		bomb.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Name = "BombStick"
		weld.Part0, weld.Part1 = hit, bomb
		weld.Parent = bomb
	end
	return true
end

bombCaster.LengthChanged:Connect(function(cast, lastPoint, rayDirection, rayDisplacement)
	local state = cast.UserData
	local bomb = state and state.bomb
	if not state or state.cleaned or state.stuck or not bomb or not bomb.Parent then return end
	-- FastCast simulates the trajectory; the anchored sphere is only its visual.
	bomb.Position = lastPoint + rayDirection * rayDisplacement
end)

bombCaster.RayHit:Connect(function(cast, result)
	local state = cast.UserData
	local bomb = state and state.bomb
	if not state or state.cleaned or not bomb then return end
	stick(bomb, state, result.Instance, result.Position + result.Normal * 0.6)
end)

bombCaster.CastTerminating:Connect(function(cast)
	local state = cast.UserData
	if state then state.cast = nil end
end)

local function newCastBehavior(state)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = state.filter
	state.raycastParams = params
	local behavior = FastCast.newBehavior()
	behavior.RaycastParams = params
	behavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)
	behavior.HighFidelityBehavior = FastCast.HighFidelityBehavior.Always
	behavior.HighFidelitySegmentSize = 0.25
	behavior.CanPierceFunction = function(_, result)
		-- Continue through thrower parts, tools, and non-solid visual effects.
		return not canStick(state, state.bomb, result.Instance)
	end
	return behavior
end

local function queueLaunch(character, humanoid, velocity, now)
	local previous = stunned[humanoid]
	stunned[humanoid] = {
		character = character,
		recover = (previous and previous.recover) or not humanoid:HasTag("Ragdoll")
			or humanoid:GetAttribute("GrappleAppliedRagdoll") == true,
	}
	humanoid:SetAttribute("BombRagdollUntil", now + Config.bombRagdollDuration)
	humanoid:SetAttribute("PhysicsServerUntil", now + SERVER_HOLD)
	humanoid:SetAttribute("RagdollActivatedAt", now)
	humanoid:SetAttribute("BombRagdollDebug", Config.bombDebugRagdoll == true)
	-- Release any grapple before launching so its rope cannot pin the victim.
	humanoid:SetAttribute("BombBlastRevision", (humanoid:GetAttribute("BombBlastRevision") or 0) + 1)
	humanoid.Sit = false
	humanoid:AddTag("Ragdoll")
	Ragdoll.Set(humanoid, true)
	Ragdoll.RefreshOwnership(humanoid)
	pendingLaunches[humanoid] = {character = character, player = Players:GetPlayerFromCharacter(character), velocity = velocity}
end

local function launch(humanoid, state, now)
	local character = state.character
	if not character.Parent or humanoid.Parent ~= character or humanoid.Health <= 0 then return end
	if state.player and state.player.Character ~= character then return end
	-- NEXT Heartbeat: allow a full physics step to rebuild the ragdoll assemblies.
	humanoid:SetAttribute("PhysicsServerUntil", now + SERVER_HOLD)
	Ragdoll.RefreshOwnership(humanoid)
	local assemblies = {}
	local bodies = {}
	local root = character:FindFirstChild("HumanoidRootPart")
	local rootAssembly = root and (root.AssemblyRootPart or root)
	if Config.bombDebugRagdoll then
		Ragdoll.ReportBombRig(humanoid, "before launch")
		local revision = humanoid:GetAttribute("BombBlastRevision")
		task.delay(0.5, function()
			if humanoid.Parent == character and humanoid:GetAttribute("BombBlastRevision") == revision then
				Ragdoll.ReportBombRig(humanoid, "airborne")
			end
		end)
	end
	for _, part in ipairs(character:GetDescendants()) do
		if not part:IsA("BasePart") then continue end
		local assembly = part.AssemblyRootPart or part
		if assemblies[assembly] then continue end
		assemblies[assembly] = true
		if not assembly.Anchored and assembly:CanSetNetworkOwnership() then
			local mass = assembly.AssemblyMass
			if mass > 0 and mass < math.huge then
				table.insert(bodies, {assembly = assembly, mass = mass,
					position = assembly.AssemblyCenterOfMass or assembly.Position, isRoot = assembly == rootAssembly})
			end
		end
	end
	BombPhysics.LaunchMotion(bodies, state.velocity, Config.bombTumbleSpeed or 3.5, Config.bombLimbKickSpeed or 3)
	for _, body in ipairs(bodies) do
		-- One bounded launch per assembly, under server ownership. No persistent
		-- mover fights the joint limits/collisions or keeps spinning after landing.
		body.assembly:ApplyImpulse((body.velocity - body.assembly.AssemblyLinearVelocity) * body.mass)
		body.assembly.AssemblyAngularVelocity = body.angular
	end
end

local function explode(bomb, position)
	-- Remove the sticky weld before any victim is ragdolled/launched.
	local bombColor = bomb.Color
	bomb:Destroy()
	local radius = Config.bombRadius
	local flash = sphere("BombBlast", 1, bombColor)
	flash.Anchored, flash.CanCollide, flash.CanTouch, flash.CanQuery = true, false, false, false
	flash.Position, flash.Transparency = position, 0.35
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.35), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1,
	}):Play()
	local sounds = Storage:FindFirstChild("Sounds")
	local sound = sounds and sounds:FindFirstChild("Explode", true)
	if sound and sound:IsA("Sound") then
		PlaySound(flash, sound)
		Debris:AddItem(flash, math.max(10, sound.TimeLength + 1))
	else
		Debris:AddItem(flash, 0.4)
	end
	for _, humanoid in ipairs(workspace:GetDescendants()) do
		if humanoid:IsA("Humanoid") and humanoid.Health > 0 then
			local character = humanoid.Parent
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and not root.Anchored then
				local velocity = BombPhysics.Knockback(root.Position - position, radius, workspace.Gravity,
					Config.bombLaunchHeight, Config.bombLaunchDistance)
				if velocity.Magnitude > 0 then queueLaunch(character, humanoid, velocity, os.clock()) end
			end
		end
	end
end

Remotes.ThrowBomb.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "Vector3" then return end
	for _, value in ipairs({target.X, target.Y, target.Z}) do
		if value ~= value or math.abs(value) > 1e7 then return end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChild(Config.bombToolName)
	if not root or not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("GrapplePhysicsLocked") then return end
	if not tool or not tool:IsA("Tool") or not tool:GetAttribute("BombTool") then return end
	local now = os.clock()
	if now - (lastThrow[player] or -math.huge) < Config.bombCooldown then return end
	lastThrow[player] = now
	local bomb = sphere("ThrownBomb", 1.2, bombColors[player:GetAttribute("BombColor")])
	local handle = tool:FindFirstChild("Handle")
	bomb.Position = handle and handle:IsA("BasePart") and handle.Position or root.Position + Vector3.new(0, 1.5, 0)
	-- This is a cosmetic shell driven by FastCast, never a competing physics body.
	bomb.Anchored, bomb.CanCollide, bomb.CanTouch, bomb.CanQuery = true, false, false, false
	bomb.Parent = workspace
	local state = {bomb = bomb, detonatesAt = now + Config.bombFuse,
		character = character, player = player, connections = {}, filter = {bomb}, ignored = {}}
	protectThrower(bomb, state, character)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then protectThrower(bomb, state, backpack) end
	table.insert(state.connections, player.CharacterAdded:Connect(function(nextCharacter)
		protectThrower(bomb, state, nextCharacter)
	end))
	table.insert(state.connections, bomb.Destroying:Connect(function() cleanupBomb(bomb, state) end))
	liveBombs[bomb] = state
	local velocity = BombPhysics.ThrowVelocity(target - bomb.Position, workspace.Gravity, Config.bombThrowSpeed, Config.bombArcHeight)
	state.cast = bombCaster:Fire(bomb.Position, velocity.Unit, velocity, newCastBehavior(state))
	state.cast.UserData = state
	hideUntilReady(tool, now + Config.bombCooldown)
	Debris:AddItem(bomb, Config.bombFuse + 1)
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for humanoid, state in pairs(pendingLaunches) do
		pendingLaunches[humanoid] = nil
		launch(humanoid, state, now)
	end
	for humanoid, state in pairs(stunned) do
		if not state.character.Parent or humanoid.Parent ~= state.character or humanoid.Health <= 0 then
			stunned[humanoid] = nil
		elseif now >= (humanoid:GetAttribute("BombRagdollUntil") or 0) and not humanoid:GetAttribute("GrapplePhysicsLocked") then
			stunned[humanoid] = nil
			humanoid:SetAttribute("BombRagdollUntil", nil)
			if state.recover then
				Ragdoll.Set(humanoid, false, true)
				humanoid:RemoveTag("Ragdoll")
			end
		end
	end
	for tool, state in pairs(coolingTools) do
		if not tool.Parent then
			coolingTools[tool] = nil
		elseif now >= state.readyAt then
			coolingTools[tool] = nil
			for part, transparency in pairs(state.parts) do
				if part.Parent then part.Transparency = transparency end
			end
			tool.Enabled = true
			tool:SetAttribute("BombCoolingDown", false)
		end
	end
	for bomb, state in pairs(liveBombs) do
		if not bomb.Parent then
			cleanupBomb(bomb, state)
		elseif now >= state.detonatesAt then
			cleanupBomb(bomb, state)
			explode(bomb, bomb.Position)
		end
	end
end)

local function added(player)
	player.CharacterAdded:Connect(function(character) task.spawn(giveBomb, player, character) end)
	if player.Character then task.spawn(giveBomb, player, player.Character) end
end
Players.PlayerAdded:Connect(added)
Players.PlayerRemoving:Connect(function(player) lastThrow[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do added(player) end

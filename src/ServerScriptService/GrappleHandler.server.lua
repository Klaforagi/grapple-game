-- Authoritative grapple simulation. Clients only provide aim and UI input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Ragdoll = require(ReplicatedStorage.Modules:WaitForChild("RagdollService"))
local Sounds = ReplicatedStorage:FindFirstChild("Sounds")
local PlaySound = require(ReplicatedStorage.Modules:WaitForChild("PlaySound"))
local function sound(name)
	return Sounds and Sounds:FindFirstChild(name)
end

local FIRE_INTERVAL = 0.05
local LENGTH_INTERVAL = 0.05
local minRopeLength = Config.minRopeLength or Config.MinRopeLength or 0.1
local maxRopeLength = Config.maxRopeLength or Config.MaxRopeLength or 500
local winchSpeed = Config.ropeLengthSpeed or 75

local hitboxFolder = Workspace:FindFirstChild("Hitbox")
if not hitboxFolder then
	hitboxFolder = Instance.new("Folder")
	hitboxFolder.Name = "Hitbox"
	hitboxFolder.Parent = Workspace
end

-- One active projectile/rope per player. Player keys avoid name collisions.
local Active: {[Player]: {[string]: any}} = {}
local GrappleOwners: {[number]: Player} = {}
local WallMode: {[Player]: boolean} = {}
local lastFire: {[Player]: number} = {}
local cooldownUntil: {[Player]: number} = {}
local lastModeToggle: {[Player]: number} = {}
local preparedTools = setmetatable({}, {__mode = "k"})

local function getTool(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.toolName)
	if tool and tool:IsA("Tool") and not preparedTools[tool] then
		preparedTools[tool] = true
		-- Decorative gun pieces must not add weight, scrape the floor, or anchor a player.
		for _, part in ipairs(tool:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored, part.CanCollide, part.Massless = false, false, true
			end
		end
		tool:SetAttribute("WallMode", WallMode[player] == true)
	end
	return tool and tool:IsA("Tool") and tool or nil
end

local function getFirePoint(tool: Tool): Attachment?
	local firePoint = tool:FindFirstChild("FirePoint", true)
	if firePoint and firePoint:IsA("Attachment") then return firePoint end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return nil end
	firePoint = Instance.new("Attachment")
	firePoint.Name = "FirePoint"
	firePoint.Position = Vector3.new(0, 0, -handle.Size.Z / 2)
	firePoint.Parent = handle
	return firePoint
end

local function setCharacterNetworkOwner(character: Model, owner: Player?)
	-- Keep every ragdoll assembly under one simulator during a drag.
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			pcall(function()
				if instance:CanSetNetworkOwnership() then
					instance:SetNetworkOwner(owner)
				end
			end)
		end
	end
end

local function restoreAutomaticNetworkOwnership(character: Model)
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			pcall(function()
				if instance:CanSetNetworkOwnership() then
					instance:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

local disconnectRope: (Player, boolean?) -> ()

disconnectRope = function(player: Player, skipCooldown: boolean?)
	local state = Active[player]
	if not state then return end
	-- Clear first so destruction and death callbacks can safely re-enter.
	Active[player] = nil

	for _, connection in pairs(state.connections) do connection:Disconnect() end
	if state.rope then state.rope:Destroy() end
	if state.pull then state.pull:Destroy() end
	if state.ownerAttachment then state.ownerAttachment:Destroy() end
	if state.impactAttachment then state.impactAttachment:Destroy() end
	if state.hitbox then state.hitbox:Destroy() end
	if state.beam and state.beam.Parent then
		state.beam.Attachment1 = state.originalBeamAttachment
		state.beam.Enabled = false
	end

	local victimHumanoid: Humanoid? = state.victimHumanoid
	if victimHumanoid and victimHumanoid.Parent then
		victimHumanoid:SetAttribute("GrappledBy", nil)
		if state.appliedRagdoll and victimHumanoid.Health > 0 then
			victimHumanoid:RemoveTag("Ragdoll")
			if victimHumanoid.Health > 0 then Ragdoll.Set(victimHumanoid, false) end
		end
	end
	if state.victimCharacter and state.ownershipTransferred then
		if state.victimPlayer and state.victimPlayer.Parent == Players then
			setCharacterNetworkOwner(state.victimCharacter, state.victimPlayer)
		else
			restoreAutomaticNetworkOwnership(state.victimCharacter)
		end
	end
	if state.victimPlayer and GrappleOwners[state.victimPlayer.UserId] == player then
		GrappleOwners[state.victimPlayer.UserId] = nil
		if state.victimPlayer.Parent == Players then Remotes.HasBeenGrappled:FireClient(state.victimPlayer) end
	end

	local tool: Tool? = state.tool
	if tool then
		tool:SetAttribute("InUse", false)
		tool:SetAttribute("HasGrappled", false)
		if not skipCooldown then
			cooldownUntil[player] = os.clock() + (Config.GrappleCooldown or 0.1)
			tool:SetAttribute("InCooldown", true)
			task.delay(Config.GrappleCooldown or 0.1, function()
				if tool.Parent then tool:SetAttribute("InCooldown", false) end
			end)
		else
			cooldownUntil[player] = nil
			tool:SetAttribute("InCooldown", false)
		end
		local bolt = tool:FindFirstChild("Bolt")
		if bolt and bolt:IsA("BasePart") then
			bolt.Transparency = 0
			PlaySound(bolt, sound("Disconnect"))
		end
	end

	-- Either the wall or player UI may be active; clear both to avoid stuck input.
	if player.Parent == Players then
		Remotes.GrappledPlayer:FireClient(player)
		Remotes.GrappledWall:FireClient(player)
	end
end

local function createImpactAttachment(player: Player, part: BasePart, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = player.Name .. " Impact"
	attachment.Parent = part
	attachment.WorldPosition = position
	return attachment
end

local function makeRope(state, firePoint: Attachment, impactAttachment: Attachment, length: number): RopeConstraint
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = firePoint
	rope.Attachment1 = impactAttachment
	rope.Length = length
	rope.WinchEnabled = true
	rope.WinchTarget = length
	rope.WinchSpeed = winchSpeed
	rope.WinchForce = Config.wallWinchForce or 5000
	rope.WinchResponsiveness = 10
	rope.Visible = true
	rope.Thickness = 0.1
	rope.Color = BrickColor.new("Black")
	rope.Parent = impactAttachment.Parent
	local visual = rope:FindFirstChild("RopeVisual")
	if visual and visual:IsA("Beam") then visual.Enabled = false end
	state.rope = rope
	state.impactAttachment = impactAttachment
	return rope
end

local function createStruggleRemote(state, victim: Player)
	state.struggleTarget = math.random(Config.minStruggleValue, Config.maxStruggleValue)
	state.struggleProgress = 0
	state.lastDecay = os.clock()
	Remotes.HasBeenGrappled:FireClient(victim, state.owner, state.struggleTarget)
end

local function characterFromPart(part)
	local ancestor = part.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			local humanoid = ancestor:FindFirstChildWhichIsA("Humanoid")
			if humanoid then return ancestor, humanoid end
		end
		ancestor = ancestor.Parent
	end
	return nil, nil
end

local function grapplePart(state, firePoint: Attachment, hit: BasePart, position: Vector3)
	if Active[state.owner] ~= state then return end
	local hitModel, hitHumanoid = characterFromPart(hit)
	if not hitHumanoid then
		if not WallMode[state.owner] then disconnectRope(state.owner) return end
		PlaySound(hit, sound("HitWall"))
		local attachment = createImpactAttachment(state.owner, hit, position)
		local rope = makeRope(state, firePoint, attachment, (firePoint.WorldPosition - position).Magnitude)
		state.tool:SetAttribute("HasGrappled", true)
		Remotes.GrappledWall:FireClient(state.owner, attachment, rope, rope:FindFirstChild("RopeVisual"))
		return
	end

	local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
	if victimPlayer == state.owner or hitHumanoid.Health <= 0 then disconnectRope(state.owner) return end
	if victimPlayer then
		-- Prevent chains/cycles: a ragdolled attacker cannot keep dragging someone.
		disconnectRope(victimPlayer, true)
		local previousOwner = GrappleOwners[victimPlayer.UserId]
		if previousOwner and previousOwner ~= state.owner then disconnectRope(previousOwner, true) end
		GrappleOwners[victimPlayer.UserId] = state.owner
	end

	-- Pull the root assembly, never an arm/leg. Limb attachments create large
	-- angular impulses in a ragdoll and were a primary source of twitching.
	local attachmentPart = hitModel:FindFirstChild("HumanoidRootPart")
	if not (attachmentPart and attachmentPart:IsA("BasePart")) then attachmentPart = hit end
	local ownerRoot = state.character:FindFirstChild("HumanoidRootPart")
	if not ownerRoot then disconnectRope(state.owner) return end
	local ownerAttachment = Instance.new("Attachment")
	ownerAttachment.Name = "GrappleDragOrigin"
	ownerAttachment.Parent = ownerRoot
	state.ownerAttachment = ownerAttachment
	local attachment = createImpactAttachment(state.owner, attachmentPart, attachmentPart.Position)
	local rope = makeRope(state, ownerAttachment, attachment, (ownerRoot.Position - attachmentPart.Position).Magnitude)
	-- Visual only: no equal-and-opposite force on the attacker's gun or arm.
	rope.Enabled = false
	rope.Visible = false
	local visual = Instance.new("Beam")
	visual.Name = "RopeVisual"
	visual.Attachment0, visual.Attachment1 = firePoint, attachment
	visual.Width0, visual.Width1 = 0.08, 0.08
	visual.FaceCamera = true
	visual.Color = ColorSequence.new(Color3.fromRGB(40, 45, 55))
	visual.Parent = rope
	state.dragLength = math.max(Config.playerMinDragDistance or 4, rope.Length)
	state.victimHumanoid = hitHumanoid
	state.victimPlayer = victimPlayer
	state.victimCharacter = hitModel
	state.appliedRagdoll = not hitHumanoid:HasTag("Ragdoll")
	if state.appliedRagdoll then
		hitHumanoid:AddTag("Ragdoll")
	end
	Ragdoll.Set(hitHumanoid, true)
	hitHumanoid:SetAttribute("GrappledBy", state.owner.UserId)
	setCharacterNetworkOwner(hitModel, state.owner)
	state.ownershipTransferred = true
	local pull = Instance.new("AlignPosition")
	pull.Name = "GrapplePull"
	pull.Mode = Enum.PositionAlignmentMode.OneAttachment
	pull.Attachment0 = attachment
	pull.ApplyAtCenterOfMass = true
	pull.ReactionForceEnabled = false
	pull.RigidityEnabled = false
	pull.Responsiveness = Config.dragResponsiveness or 12
	pull.MaxVelocity = Config.dragMaxSpeed or 45
	local mass = 0
	for _, part in ipairs(hitModel:GetChildren()) do
		if part:IsA("BasePart") then mass += part:GetMass() end
	end
	pull.MaxForce = math.max(1, mass) * (Workspace.Gravity + (Config.dragAcceleration or 100))
	pull.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	pull.ForceRelativeTo = Enum.ActuatorRelativeTo.World
	-- Drag along the floor; never use the pull to support the victim's weight.
	pull.MaxAxesForce = Vector3.new(pull.MaxForce, 0, pull.MaxForce)
	pull.Position = attachmentPart.Position
	pull.Enabled = false
	pull.Parent = attachmentPart
	state.pull = pull
	if victimPlayer then
		createStruggleRemote(state, victimPlayer)
	end
	state.connections.victimDied = hitHumanoid.Died:Connect(function()
		if Active[state.owner] == state then disconnectRope(state.owner, true) end
	end)
	state.tool:SetAttribute("HasGrappled", true)
	PlaySound(state.tool:FindFirstChild("Handle"), sound("Grapple"))
	Remotes.GrappledPlayer:FireClient(state.owner, hitModel, rope, rope:FindFirstChild("RopeVisual"))
end

local function isValidAim(player: Player, hitPosition: any, cameraPosition: any): boolean
	if typeof(hitPosition) ~= "Vector3" or typeof(cameraPosition) ~= "Vector3" then return false end
	local function finite(vector)
		return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
			and math.abs(vector.X) < 1e7 and math.abs(vector.Y) < 1e7 and math.abs(vector.Z) < 1e7
	end
	if not finite(hitPosition) or not finite(cameraPosition) then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- The projectile always starts at the equipped gun. Camera zoom/lag is not
	-- a reason to reject an otherwise finite aim direction.
	return root ~= nil
end

local function findCharacterHit(parts: {BasePart}, startPosition: Vector3, direction: Vector3): BasePart?
	local chosen, nearest = nil, math.huge
	for _, part in ipairs(parts) do
		if not part:FindFirstAncestorOfClass("Accessory") and not part:FindFirstAncestorOfClass("Tool") then
			local model = characterFromPart(part)
			if model then
				local distance = math.max(0, (part.Position - startPosition):Dot(direction))
				if distance < nearest then chosen, nearest = part, distance end
			end
		end
	end
	return chosen
end

local function createHitbox(state, origin: Vector3, direction: Vector3): BasePart
	local hitbox = Instance.new("Part")
	hitbox.Name = state.owner.Name .. " Hitbox"
	hitbox.Size = Config.HitboxSize or Vector3.new(0.5, 0.5, 0.5)
	hitbox.Anchored, hitbox.CanCollide, hitbox.CanQuery = true, false, false
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox.Material = Enum.Material.Neon
	hitbox.Transparency = Config.debugMode and 0 or 1
	hitbox.CFrame = CFrame.new(origin, origin + direction)
	hitbox.Parent = hitboxFolder
	state.hitbox = hitbox
	return hitbox
end

Remotes.ChangeLength.OnServerEvent:Connect(function(player, requestedLength)
	local state = Active[player]
	if not state or not state.rope or typeof(requestedLength) ~= "number" then return end
	if requestedLength ~= requestedLength or math.abs(requestedLength) == math.huge then return end
	local now = os.clock()
	if state.lastLengthChange and now - state.lastLengthChange < LENGTH_INTERVAL then return end
	state.lastLengthChange = now
	local length = math.clamp(requestedLength, minRopeLength, maxRopeLength)
	local previous = state.rope.WinchTarget
	local maxStep = (Config.ropeLengthStep or 2) * 2
	length = math.clamp(length, previous - maxStep, previous + maxStep)
	if state.pull then length = math.max(Config.playerMinDragDistance or 4, length) end
	state.rope.WinchTarget = length
	if state.pull then state.rope.Length = length end
end)

Remotes.ToggleWallMode.OnServerEvent:Connect(function(player)
	if not getTool(player) then return end
	local now = os.clock()
	if now - (lastModeToggle[player] or -math.huge) < 0.15 then return end
	lastModeToggle[player] = now
	WallMode[player] = not (WallMode[player] == true)
	local tool = getTool(player)
	if tool then tool:SetAttribute("WallMode", WallMode[player]) end
end)

local function fireGrapple(player, hitPosition, cameraPosition)
	local now = os.clock()
	if lastFire[player] and now - lastFire[player] < FIRE_INTERVAL then return end
	lastFire[player] = now
	if Active[player] then disconnectRope(player) return end
	if not isValidAim(player, hitPosition, cameraPosition) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local tool = getTool(player)
	local firePoint = tool and getFirePoint(tool)
	if not character or not humanoid or humanoid.Health <= 0 or humanoid:HasTag("Ragdoll") or not tool or not firePoint then return end
	if os.clock() < (cooldownUntil[player] or 0) then return end
	local aim = hitPosition - firePoint.WorldPosition
	if aim.Magnitude < 0.01 then return end

	local origin, direction = firePoint.WorldPosition, aim.Unit
	local state = { owner = player, tool = tool, character = character, connections = {} }
	Active[player] = state
	tool:SetAttribute("InUse", true)
	tool:SetAttribute("InCooldown", true)
	local beam = tool:FindFirstChild("Rope")
	if beam and beam:IsA("Beam") then beam.Enabled = true end
	local bolt = tool:FindFirstChild("Bolt")
	if bolt and bolt:IsA("BasePart") then bolt.Transparency = 1 end
	PlaySound(tool:FindFirstChild("Handle"), sound("Fire"))
	state.connections.ownerDied = humanoid.Died:Connect(function() disconnectRope(player, true) end)
	state.connections.toolUnequipped = tool.Unequipped:Connect(function() disconnectRope(player) end)
	state.connections.toolDestroyed = tool.Destroying:Connect(function() disconnectRope(player, true) end)
	local hitbox = createHitbox(state, origin, direction)
	if beam and beam:IsA("Beam") then
		local flightAttachment = Instance.new("Attachment")
		flightAttachment.Name = "GrappleFlightAttachment"
		flightAttachment.Parent = hitbox
		state.beam = beam
		state.originalBeamAttachment = beam.Attachment1
		beam.Attachment1 = flightAttachment
	end
	Remotes.FireGrapple:FireClient(player, hitbox)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character, tool, hitboxFolder}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character, tool, hitboxFolder}
	local travelled, lastPosition, accumulator = 0, origin, 0
	while Active[player] == state and travelled < maxRopeLength do
		accumulator += RunService.Heartbeat:Wait()
		if Active[player] ~= state then break end
		if accumulator < (1 / 30) then continue end
		local dt = math.min(accumulator, 0.1)
		accumulator = 0
		local nextTravelled = math.min(travelled + (Config.HookSpeed or 80) * dt, maxRopeLength)
		local nextPosition = origin + direction * nextTravelled
		hitbox.CFrame = CFrame.new(nextPosition, nextPosition + direction)
		local hit, impactPosition = nil, nil
		if WallMode[player] then
			local result = Workspace:Raycast(lastPosition, nextPosition - lastPosition, rayParams)
			if result and result.Instance:IsA("BasePart") then hit, impactPosition = result.Instance, result.Position end
		else
			local segment = nextPosition - lastPosition
			local size = hitbox.Size
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(lastPosition + segment / 2, lastPosition + segment / 2 + direction), Vector3.new(size.X, size.Y, segment.Magnitude + size.Z), overlapParams)
			hit = findCharacterHit(parts, lastPosition, direction)
			impactPosition = hit and hit.Position or nil
			-- Overlap boxes see through solid walls; verify the selected target is visible.
			if hit then
				local obstruction = Workspace:Raycast(lastPosition, impactPosition - lastPosition, rayParams)
				if obstruction and characterFromPart(obstruction.Instance) ~= characterFromPart(hit) then
					disconnectRope(player)
					break
				end
			end
		end
		if hit and impactPosition then grapplePart(state, firePoint, hit, impactPosition) break end
		travelled, lastPosition = nextTravelled, nextPosition
	end

	-- A cancelled projectile may resume after a newer shot. It must not reset that shot.
	if Active[player] ~= state then return end
	if not state.rope then disconnectRope(player) return end
	if Active[player] == state and state.hitbox then state.hitbox:Destroy() state.hitbox = nil end
	if beam and beam:IsA("Beam") then
		beam.Attachment1 = state.originalBeamAttachment
		beam.Enabled = false
	end
	tool:SetAttribute("InUse", false)
end

Remotes.FireGrapple.OnServerEvent:Connect(function(player, hitPosition, cameraPosition)
	local ok, message = xpcall(function()
		fireGrapple(player, hitPosition, cameraPosition)
	end, debug.traceback)
	if not ok then
		-- A malformed rig/asset must not leave a half-created shot locking the gun.
		disconnectRope(player, true)
		warn("[Grapple] Shot failed and was released: " .. tostring(message))
	end
end)

local function decayStruggle(state, now)
	if not state.struggleTarget or not Config.struggleDecrease then return end
	local interval = math.max(0.1, Config.struggleDecreaseInterval or 1)
	local ticks = math.floor((now - state.lastDecay) / interval)
	if ticks > 0 then
		state.lastDecay += ticks * interval
		state.struggleProgress = math.max(0, state.struggleProgress - ticks * Config.struggleDecreaseAmt)
		if state.victimPlayer and state.victimPlayer.Parent == Players then
			Remotes.StruggleProgress:FireClient(state.victimPlayer, state.struggleProgress, state.struggleTarget)
		end
	end
end

Remotes.StruggleInput.OnServerEvent:Connect(function(victim)
	local owner = GrappleOwners[victim.UserId]
	local state = owner and Active[owner]
	if not state or state.victimPlayer ~= victim or not state.struggleTarget then return end
	local now = os.clock()
	if state.lastStruggleInput and now - state.lastStruggleInput < 0.075 then return end
	state.lastStruggleInput = now
	decayStruggle(state, now)
	state.struggleProgress += Config.struggleIncrement
	if state.struggleProgress >= state.struggleTarget then disconnectRope(owner) return end
	Remotes.StruggleProgress:FireClient(victim, state.struggleProgress, state.struggleTarget)
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for owner, state in pairs(Active) do
		if state.rope then
			local a0, a1 = state.rope.Attachment0, state.rope.Attachment1
			if not a0 or not a0.Parent or not a1 or not a1.Parent then
				disconnectRope(owner)
				continue
			end
			if state.pull then
				local desired = math.max(Config.playerMinDragDistance or 4, state.rope.WinchTarget)
				local step = winchSpeed * dt
				state.dragLength += math.clamp(desired - state.dragLength, -step, step)
				local offset = a1.WorldPosition - a0.WorldPosition
				state.pull.Enabled = offset.Magnitude > state.dragLength + 0.25
				if offset.Magnitude > 0.001 then
					state.pull.Position = a0.WorldPosition + offset.Unit * state.dragLength
				end
			end
			decayStruggle(state, now)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectRope(player, true)
	local owner = GrappleOwners[player.UserId]
	if owner then disconnectRope(owner, true) end
	WallMode[player], lastFire[player], cooldownUntil[player] = nil, nil, nil
	lastModeToggle[player] = nil
end)

local function watchPlayer(player: Player)
	player.CharacterRemoving:Connect(function()
		disconnectRope(player, true)
		local owner = GrappleOwners[player.UserId]
		if owner then disconnectRope(owner, true) end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

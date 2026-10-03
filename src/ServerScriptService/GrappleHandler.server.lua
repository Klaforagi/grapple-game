-- Authoritative grapple simulation. Clients only provide aim and UI input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local Sounds = ReplicatedStorage:WaitForChild("Sounds")
local PlaySound = require(ReplicatedStorage.Modules:WaitForChild("PlaySound"))

local FIRE_INTERVAL = 0.05
local LENGTH_INTERVAL = 0.05
local MAX_CAMERA_OFFSET = 20
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

local function getTool(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.toolName)
	return tool and tool:IsA("Tool") and tool or nil
end

local function getFirePoint(tool: Tool): Attachment?
	local firePoint = tool:FindFirstChild("FirePoint", true)
	return firePoint and firePoint:IsA("Attachment") and firePoint or nil
end

local function setCharacterNetworkOwner(character: Model, owner: Player?)
	-- The victim must have one simulator. A rope between two client-owned player
	-- assemblies produces the correction war that makes dragged players jitter.
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
	if state.impactAttachment then state.impactAttachment:Destroy() end
	if state.struggleRemote then state.struggleRemote:Destroy() end
	if state.hitbox then state.hitbox:Destroy() end
	if state.beam and state.beam.Parent then
		state.beam.Attachment1 = state.originalBeamAttachment
		state.beam.Enabled = false
	end

	local victimHumanoid: Humanoid? = state.victimHumanoid
	if victimHumanoid and victimHumanoid.Parent then
		victimHumanoid:SetAttribute("GrappledBy", nil)
		if state.appliedRagdoll then
			victimHumanoid:RemoveTag("Ragdoll")
			victimHumanoid.PlatformStand = false
			if victimHumanoid.Health > 0 then victimHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
		end
	end
	if state.victimCharacter and state.serverOwnedVictim then
		restoreAutomaticNetworkOwnership(state.victimCharacter)
	end
	if state.victimPlayer and GrappleOwners[state.victimPlayer.UserId] == player then
		GrappleOwners[state.victimPlayer.UserId] = nil
	end

	local tool: Tool? = state.tool
	if tool then
		tool:SetAttribute("InUse", false)
		tool:SetAttribute("HasGrappled", false)
		if not skipCooldown then
			tool:SetAttribute("InCooldown", true)
			task.delay(Config.GrappleCooldown or 0.1, function()
				if tool.Parent then tool:SetAttribute("InCooldown", false) end
			end)
		end
		local bolt = tool:FindFirstChild("Bolt")
		if bolt and bolt:IsA("BasePart") then
			bolt.Transparency = 0
			PlaySound(bolt, Sounds:FindFirstChild("Disconnect"))
		end
	end

	-- Either the wall or player UI may be active; clear both to avoid stuck input.
	Remotes.GrappledPlayer:FireClient(player)
	Remotes.GrappledWall:FireClient(player)
end

local function createImpactAttachment(player: Player, part: BasePart, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = player.Name .. " Impact"
	attachment.Parent = part
	attachment.WorldPosition = position
	return attachment
end

local function makeRope(state, firePoint: Attachment, impactAttachment: Attachment, length: number): RopeConstraint
	local rope = Templates:WaitForChild("RopeConstraint"):Clone()
	rope.Attachment0 = firePoint
	rope.Attachment1 = impactAttachment
	rope.Length = length
	rope.WinchEnabled = true
	rope.WinchTarget = length
	rope.WinchSpeed = winchSpeed
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
	local folder = ReplicatedStorage:FindFirstChild("Struggle")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Struggle"
		folder.Parent = ReplicatedStorage
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = string.format("Grapple_%d_%d", victim.UserId, math.floor(os.clock() * 1000))
	remote.Parent = folder
	state.struggleRemote = remote
	state.connections.struggle = remote.OnServerEvent:Connect(function(sender)
		if sender == victim and Active[state.owner] == state then disconnectRope(state.owner) end
	end)
	Remotes.HasBeenGrappled:FireClient(victim, state.owner, remote.Name)
end

local function grapplePart(state, firePoint: Attachment, hit: BasePart, position: Vector3)
	if Active[state.owner] ~= state then return end
	local hitModel = hit:FindFirstAncestorOfClass("Model")
	local hitHumanoid = hitModel and hitModel:FindFirstChildWhichIsA("Humanoid")
	if not hitHumanoid then
		if not WallMode[state.owner] then disconnectRope(state.owner) return end
		PlaySound(hit, Sounds:FindFirstChild("HitWall"))
		local attachment = createImpactAttachment(state.owner, hit, position)
		local rope = makeRope(state, firePoint, attachment, (firePoint.WorldPosition - position).Magnitude)
		state.tool:SetAttribute("HasGrappled", true)
		Remotes.GrappledWall:FireClient(state.owner, attachment, rope, rope:FindFirstChild("RopeVisual"))
		return
	end

	local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
	if victimPlayer == state.owner or hitHumanoid.Health <= 0 then disconnectRope(state.owner) return end
	if victimPlayer then
		local previousOwner = GrappleOwners[victimPlayer.UserId]
		if previousOwner and previousOwner ~= state.owner then disconnectRope(previousOwner, true) end
		GrappleOwners[victimPlayer.UserId] = state.owner
	end

	-- Pull the root assembly, never an arm/leg. Limb attachments create large
	-- angular impulses in a ragdoll and were a primary source of twitching.
	local attachmentPart = hitModel:FindFirstChild("HumanoidRootPart")
	if not (attachmentPart and attachmentPart:IsA("BasePart")) then attachmentPart = hit end
	local attachment = createImpactAttachment(state.owner, attachmentPart, position)
	local rope = makeRope(state, firePoint, attachment, (firePoint.WorldPosition - position).Magnitude)
	state.victimHumanoid = hitHumanoid
	state.victimPlayer = victimPlayer
	state.victimCharacter = hitModel
	state.appliedRagdoll = not hitHumanoid:HasTag("Ragdoll")
	if state.appliedRagdoll then
		hitHumanoid:AddTag("Ragdoll")
		hitHumanoid.PlatformStand = true
		hitHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	hitHumanoid:SetAttribute("GrappledBy", state.owner.UserId)
	if victimPlayer then
		setCharacterNetworkOwner(hitModel, nil)
		state.serverOwnedVictim = true
		createStruggleRemote(state, victimPlayer)
	end
	state.connections.victimDied = hitHumanoid.Died:Connect(function()
		if Active[state.owner] == state then disconnectRope(state.owner, true) end
	end)
	state.tool:SetAttribute("HasGrappled", true)
	PlaySound(state.tool:FindFirstChild("Handle"), Sounds:FindFirstChild("Grapple"))
	Remotes.GrappledPlayer:FireClient(state.owner, hitModel, rope, rope:FindFirstChild("RopeVisual"))
end

local function isValidAim(player: Player, hitPosition: any, cameraPosition: any): boolean
	if typeof(hitPosition) ~= "Vector3" or typeof(cameraPosition) ~= "Vector3" then return false end
	if hitPosition ~= hitPosition or cameraPosition ~= cameraPosition then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (cameraPosition - root.Position).Magnitude <= MAX_CAMERA_OFFSET
end

local function findCharacterHit(parts: {BasePart}, startPosition: Vector3, direction: Vector3): BasePart?
	local chosen, nearest = nil, math.huge
	for _, part in ipairs(parts) do
		if not part:FindFirstAncestorOfClass("Accessory") and not part:FindFirstAncestorOfClass("Tool") then
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildWhichIsA("Humanoid") then
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
	state.rope.WinchTarget = length
	-- WinchTarget drives the normal smooth animation. Updating Length too makes
	-- Q/E reliable on older RopeConstraint templates whose winch settings were
	-- saved with insufficient force/responsiveness.
	state.rope.Length = length
end)

Remotes.ToggleWallMode.OnServerEvent:Connect(function(player)
	WallMode[player] = not (WallMode[player] == true)
	local tool = getTool(player)
	if tool then tool:SetAttribute("WallMode", WallMode[player]) end
end)

Remotes.FireGrapple.OnServerEvent:Connect(function(player, hitPosition, cameraPosition)
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
	if tool:GetAttribute("InCooldown") then return end
	local aim = hitPosition - cameraPosition
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
	PlaySound(tool:FindFirstChild("Handle"), Sounds:FindFirstChild("Fire"))
	state.connections.ownerDied = humanoid.Died:Connect(function() disconnectRope(player, true) end)
	state.connections.toolUnequipped = tool.Unequipped:Connect(function() disconnectRope(player) end)
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
		end
		if hit and impactPosition then grapplePart(state, firePoint, hit, impactPosition) break end
		travelled, lastPosition = nextTravelled, nextPosition
	end

	if Active[player] == state and not state.rope then disconnectRope(player) end
	if Active[player] == state and state.hitbox then state.hitbox:Destroy() state.hitbox = nil end
	if beam and beam:IsA("Beam") then
		beam.Attachment1 = state.originalBeamAttachment
		beam.Enabled = false
	end
	tool:SetAttribute("InUse", false)
	if not state.rope then
		if bolt and bolt:IsA("BasePart") then bolt.Transparency = 0 end
		task.delay(Config.GrappleCooldown or 0.1, function()
			if tool.Parent then tool:SetAttribute("InCooldown", false) end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectRope(player, true)
	WallMode[player], lastFire[player] = nil, nil
end)

local function watchPlayer(player: Player)
	player.CharacterRemoving:Connect(function() disconnectRope(player, true) end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

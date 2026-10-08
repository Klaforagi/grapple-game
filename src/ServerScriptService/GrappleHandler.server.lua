-- Server validates grapples; the grappler simulates the connected mechanism.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Ragdoll = require(ReplicatedStorage.Modules:WaitForChild("RagdollService"))
local ToolSetup = require(ReplicatedStorage.Modules:WaitForChild("GrappleToolSetup"))
local Sounds = ReplicatedStorage:FindFirstChild("Sounds")
local PlaySound = require(ReplicatedStorage.Modules:WaitForChild("PlaySound"))
local function sound(name)
	return Sounds and Sounds:FindFirstChild(name)
end

local FIRE_INTERVAL = 0.05
local LENGTH_INTERVAL = Config.ropeReelInterval or 1 / 15
local minRopeLength = Config.minRopeLength or Config.MinRopeLength or 0.1
local maxRopeLength = Config.maxRopeLength or Config.MaxRopeLength or 500
local releaseGrapple = ServerStorage:FindFirstChild("ReleaseGrapple")
if not releaseGrapple then
	releaseGrapple = Instance.new("BindableEvent")
	releaseGrapple.Name = "ReleaseGrapple"
	releaseGrapple.Parent = ServerStorage
end

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
-- Includes detached victims awaiting handoff. Identity guards invalidate old timers.
local physicsSessions = {}
local nextPhysicsSession = 0
local cosmeticColors = {
	Black = Color3.fromRGB(20, 20, 20), White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(220, 55, 55),
	Orange = Color3.fromRGB(242, 143, 43), Yellow = Color3.fromRGB(245, 220, 55), Green = Color3.fromRGB(65, 180, 90),
	Blue = Color3.fromRGB(55, 125, 230), Purple = Color3.fromRGB(145, 82, 210), Pink = Color3.fromRGB(240, 105, 175),
	Cyan = Color3.fromRGB(35, 210, 225), Teal = Color3.fromRGB(35, 155, 145), Lime = Color3.fromRGB(150, 225, 55),
}

local function applyCosmetics(player: Player, tool: Tool?)
	if not tool then return end
	local gunColor = cosmeticColors[player:GetAttribute("GrappleGunColor")]
	if gunColor then
		for _, instance in ipairs(tool:GetDescendants()) do
			if instance:IsA("BasePart") then instance.Color = gunColor end
		end
		local bolt = tool:FindFirstChild("Bolt", true)
		if bolt and bolt:IsA("BasePart") then bolt.Color = gunColor end
	end
	local ropeColor = cosmeticColors[player:GetAttribute("GrappleRopeColor")]
	local beam = tool:FindFirstChild("Rope")
	if ropeColor and beam and beam:IsA("Beam") then beam.Color = ColorSequence.new(ropeColor) end
	local state = Active[player]
	if ropeColor and state and state.rope then state.rope.Color = BrickColor.new(ropeColor) end
end

local function findInventoryTool(player: Player, name: string): Tool?
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = (character and character:FindFirstChild(name)) or (backpack and backpack:FindFirstChild(name))
	return tool and tool:IsA("Tool") and tool or nil
end

local function getTool(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.toolName)
	if tool and tool:IsA("Tool") and not preparedTools[tool] then
		preparedTools[tool] = true
		ToolSetup.Prepare(tool, true)
		tool:SetAttribute("WallMode", WallMode[player] == true)
	end
	if tool and tool:IsA("Tool") then applyCosmetics(player, tool) end
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

local disconnectRope: (Player, boolean?, boolean?) -> ()

local function finishVictimHandoff(state, departingPlayer)
	local character, humanoid = state.victimCharacter, state.victimHumanoid
	if physicsSessions[character] ~= state then return end
	physicsSessions[character] = nil
	local victim = state.victimPlayer
	if character.Parent and humanoid.Parent == character then
		humanoid:SetAttribute("GrapplePhysicsOwner", nil)
		humanoid:SetAttribute("GrappleAppliedRagdoll", nil)
		-- The rope is already gone. Preserve flight momentum and never teleport
		-- to the server's possibly older copy of the owner's last position.
		if victim and victim ~= departingPlayer and victim.Parent == Players and victim.Character == character then
			Ragdoll.RefreshOwnership(humanoid)
		else
			restoreAutomaticNetworkOwnership(character)
		end
		humanoid:SetAttribute("GrapplePhysicsLocked", nil)
		humanoid:SetAttribute("GrapplePhysicsSession", nil)
		if humanoid:HasTag("Ragdoll") then Ragdoll.Set(humanoid, true) end
		if state.appliedRagdoll and humanoid.Health > 0
			and os.clock() >= (humanoid:GetAttribute("BombRagdollUntil") or 0)
			and os.clock() >= (humanoid:GetAttribute("ForcedRagdollUntil") or 0) then
			-- Set before removing the tag so its observer cannot run pose recovery.
			Ragdoll.Set(humanoid, false, true)
			humanoid:RemoveTag("Ragdoll")
		end
	end
	if victim and victim.Parent == Players then
		Remotes.GrappleVictimState:FireClient(victim, character, state.physicsSession, false)
	end
end

disconnectRope = function(player: Player, skipCooldown: boolean?, preserveVictimMomentum: boolean?)
	local state = Active[player]
	if not state then return end
	-- Clear first so destruction and death callbacks can safely re-enter.
	Active[player] = nil

	for _, connection in pairs(state.connections) do connection:Disconnect() end
	if state.rope then state.rope:Destroy() end
	if state.ownerAttachment then state.ownerAttachment:Destroy() end
	if state.impactAttachment then state.impactAttachment:Destroy() end
	if state.hitbox then state.hitbox:Destroy() end
	if state.beam and state.beam.Parent then
		state.beam.Attachment1 = state.originalBeamAttachment
		state.beam.Enabled = false
	end

	local victimHumanoid: Humanoid? = state.victimHumanoid
	if victimHumanoid and physicsSessions[state.victimCharacter] == state then
		local forcedDuration = math.max(0, Config.playerReleaseRagdollDuration or 1)
		if preserveVictimMomentum then
			state.forcedRagdollUntil = os.clock() + forcedDuration
			victimHumanoid:SetAttribute("ForcedRagdollUntil", state.forcedRagdollUntil)
		end
		if victimHumanoid.Parent then victimHumanoid:SetAttribute("GrappledBy", nil) end
		-- Let the current simulator finish the detached motion before handing
		-- it back. A click/tap release keeps the grappler as simulator for the
		-- complete forced-ragdoll window so ownership cannot interrupt momentum.
		state.detached = true
		local handoffDelay = math.clamp(Config.playerOwnershipReleaseDelay or 0.2, 0, 1)
		if preserveVictimMomentum then handoffDelay = math.max(handoffDelay, forcedDuration) end
		task.delay(handoffDelay, function()
			finishVictimHandoff(state)
		end)
		if state.forcedRagdollUntil then
			local deadline = state.forcedRagdollUntil
			task.delay(forcedDuration, function()
				if victimHumanoid.Parent ~= state.victimCharacter
					or victimHumanoid:GetAttribute("ForcedRagdollUntil") ~= deadline then return end
				victimHumanoid:SetAttribute("ForcedRagdollUntil", nil)
				if state.appliedRagdoll and victimHumanoid.Health > 0
					and not victimHumanoid:GetAttribute("GrapplePhysicsLocked")
					and physicsSessions[state.victimCharacter] == nil
					and os.clock() >= (victimHumanoid:GetAttribute("BombRagdollUntil") or 0) then
					Ragdoll.Set(victimHumanoid, false, true)
					victimHumanoid:RemoveTag("Ragdoll")
				end
			end)
		end
	end
	if state.ownershipTransferred and state.character.Parent then
		local ownerHumanoid = state.character:FindFirstChildOfClass("Humanoid")
		if ownerHumanoid and not ownerHumanoid:GetAttribute("GrapplePhysicsLocked") then
			restoreAutomaticNetworkOwnership(state.character)
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

releaseGrapple.Event:Connect(function(player)
	if player and player:IsA("Player") then disconnectRope(player, true, false) end
end)

local function createImpactAttachment(player: Player, part: BasePart, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = player.Name .. " Impact"
	attachment.Parent = part
	attachment.WorldPosition = position
	return attachment
end

local function ropeColorFromTool(tool: Tool?): BrickColor
	local beam = tool and tool:FindFirstChild("Rope")
	if beam and beam:IsA("Beam") then
		local keypoints = beam.Color.Keypoints
		if #keypoints > 0 then
			-- RopeConstraint has a single BrickColor while Beam supports a color
			-- sequence. Use the beam's leading color (or the whole color when it
			-- is solid), converted to the closest supported rope color.
			return BrickColor.new(keypoints[1].Value)
		end
	end
	return BrickColor.new("Black")
end

local function makeRope(state, firePoint: Attachment, impactAttachment: Attachment, length: number): RopeConstraint
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = firePoint
	rope.Attachment1 = impactAttachment
	rope.Length = length
	rope.WinchEnabled = false
	rope.Restitution = 0
	rope.Visible = true
	rope.Thickness = 0.1
	rope.Color = ropeColorFromTool(state.tool)
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
		-- Wall ropes originate at the gun itself. FirePoint is part of the tool
		-- rig, so do not register it for session cleanup.
		local rope = makeRope(state, firePoint, attachment, (firePoint.WorldPosition - position).Magnitude)
		state.tool:SetAttribute("HasGrappled", true)
		Remotes.GrappledWall:FireClient(state.owner, attachment, rope, rope:FindFirstChild("RopeVisual"))
		return
	end

	-- A player hit always uses the normal grapple behavior. Leaving wall mode
	-- here keeps the next shot aimed at players unless the owner enables it again.
	if WallMode[state.owner] then
		WallMode[state.owner] = false
		state.tool:SetAttribute("WallMode", false)
	end
	local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
	if victimPlayer == state.owner or hitHumanoid.Health <= 0 then disconnectRope(state.owner) return end
	local previousSession = physicsSessions[hitModel]
	if previousSession and Active[previousSession.owner] == previousSession then
		disconnectRope(previousSession.owner, true)
	end
	if victimPlayer then
		-- Prevent chains/cycles: a ragdolled attacker cannot keep dragging someone.
		disconnectRope(victimPlayer, true)
		local previousOwner = GrappleOwners[victimPlayer.UserId]
		if previousOwner and previousOwner ~= state.owner then disconnectRope(previousOwner, true) end
	end

	-- Connect the root assemblies, never an arm/leg. Limb attachments create
	-- large angular impulses in a ragdoll and make the rope unstable.
	local attachmentPart = hitModel:FindFirstChild("HumanoidRootPart")
	if not (attachmentPart and attachmentPart:IsA("BasePart")) then disconnectRope(state.owner) return end
	local ownerRoot = state.character:FindFirstChild("HumanoidRootPart")
	if not ownerRoot then disconnectRope(state.owner) return end
	local ownerAttachment = Instance.new("Attachment")
	ownerAttachment.Name = "GrappleDragOrigin"
	ownerAttachment.Parent = ownerRoot
	state.ownerAttachment = ownerAttachment
	local attachment = createImpactAttachment(state.owner, attachmentPart, attachmentPart.Position)
	local rope = makeRope(state, ownerAttachment, attachment, (ownerRoot.Position - attachmentPart.Position).Magnitude)
	-- Both modes use a fixed maximum separation with no winch motor.
	rope:SetAttribute("PlayerGrapple", true)
	state.releaseAllowedAt = os.clock() + (Config.playerReleaseCooldown or 0.3)
	state.victimHumanoid = hitHumanoid
	state.victimPlayer = victimPlayer
	state.victimCharacter = hitModel
	if victimPlayer then GrappleOwners[victimPlayer.UserId] = state.owner end
	state.appliedRagdoll = (previousSession and previousSession.appliedRagdoll) or not hitHumanoid:HasTag("Ragdoll")
	hitHumanoid:SetAttribute("GrappleAppliedRagdoll", state.appliedRagdoll)
	nextPhysicsSession += 1
	state.physicsSession = nextPhysicsSession
	physicsSessions[hitModel] = state
	hitHumanoid:SetAttribute("GrapplePhysicsOwner", state.owner.UserId)
	hitHumanoid:SetAttribute("GrapplePhysicsSession", state.physicsSession)
	hitHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	if victimPlayer then
		Remotes.GrappleVictimState:FireClient(victimPlayer, hitModel, state.physicsSession, true)
	end
	if state.appliedRagdoll then
		hitHumanoid:AddTag("Ragdoll")
	end
	Ragdoll.Set(hitHumanoid, true)
	hitHumanoid:SetAttribute("GrappledBy", state.owner.UserId)
	state.ownershipTransferred = true
	if not Ragdoll.RefreshOwnership(hitHumanoid) then
		warn("[Grapple] Victim root cannot be assigned to the grappler; releasing tether")
		disconnectRope(state.owner, true)
		return
	end
	if victimPlayer then
		createStruggleRemote(state, victimPlayer)
	end
	state.connections.victimDied = hitHumanoid.Died:Connect(function()
		if Active[state.owner] == state then disconnectRope(state.owner, true) end
	end)
	state.connections.victimBlasted = hitHumanoid:GetAttributeChangedSignal("BombBlastRevision"):Connect(function()
		if Active[state.owner] == state then disconnectRope(state.owner, true) end
	end)
	state.connections.victimDestroyed = hitModel.Destroying:Connect(function()
		if Active[state.owner] == state then disconnectRope(state.owner, true) end
	end)
	state.tool:SetAttribute("HasGrappled", true)
	PlaySound(state.tool:FindFirstChild("Handle"), sound("Grapple"))
	Remotes.GrappledPlayer:FireClient(state.owner, hitModel, rope)
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
	local previousChange = state.lastLengthChange
	if previousChange and now - previousChange < LENGTH_INTERVAL then return end
	state.lastLengthChange = now
	local minimum = state.victimHumanoid and (Config.playerMinDragDistance or 4) or minRopeLength
	local length = math.clamp(requestedLength, minimum, maxRopeLength)
	local previousLength = state.rope.Length
	-- Store the actual constraint length immediately. It cannot unwind when
	-- input stops and does not depend on winch force or target convergence.
	state.rope.Length = length

	-- Rope tension is equal at both ends, which can pull the grappler toward a
	-- resistant victim. Reel-in gets a one-sided assist on the victim assembly.
	if state.victimHumanoid and length < previousLength - 0.001 then
		local ownerRoot = state.character:FindFirstChild("HumanoidRootPart")
		local victimRoot = state.victimCharacter and state.victimCharacter:FindFirstChild("HumanoidRootPart")
		if ownerRoot and ownerRoot:IsA("BasePart") and victimRoot and victimRoot:IsA("BasePart")
			and not victimRoot.Anchored then
			local offset = ownerRoot.Position - victimRoot.Position
			if offset.Magnitude > (Config.playerMinDragDistance or 4) then
				local direction = offset.Unit
				local currentSpeed = victimRoot.AssemblyLinearVelocity:Dot(direction)
				local desiredSpeed = Config.playerReelVictimPullSpeed or 22
				local boost = math.clamp(desiredSpeed - currentSpeed, 0,
					Config.playerReelVictimMaxBoost or 30)
				if boost > 0 then
					victimRoot:ApplyImpulse(direction * victimRoot.AssemblyMass * boost)
				end
			end
		end
	end
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

Remotes.SetGrappleColor.OnServerEvent:Connect(function(player, target, colorName)
	if (target ~= "Gun" and target ~= "Rope" and target ~= "Bomb") or typeof(colorName) ~= "string" or not cosmeticColors[colorName] then return end
	if target == "Bomb" then
		player:SetAttribute("BombColor", colorName)
		local bomb = findInventoryTool(player, Config.bombToolName)
		local handle = bomb and bomb:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then handle.Color = cosmeticColors[colorName] end
		return
	end
	player:SetAttribute(target == "Gun" and "GrappleGunColor" or "GrappleRopeColor", colorName)
	applyCosmetics(player, findInventoryTool(player, Config.toolName))
end)

local function fireGrapple(player, hitPosition, cameraPosition)
	local now = os.clock()
	if lastFire[player] and now - lastFire[player] < FIRE_INTERVAL then return end
	lastFire[player] = now
	if Active[player] then
		if now < (Active[player].releaseAllowedAt or 0) then return end
		disconnectRope(player, false, true)
		return
	end
	if not isValidAim(player, hitPosition, cameraPosition) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local tool = getTool(player)
	local firePoint = tool and getFirePoint(tool)
	if not character or not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("GrapplePhysicsLocked")
		or humanoid:GetAttribute("CapsuleLocked")
		or not tool or not firePoint then return end
	if os.clock() < (cooldownUntil[player] or 0) then return end
	local aim = hitPosition - firePoint.WorldPosition
	if aim.Magnitude < 0.01 then return end

	local origin, direction = firePoint.WorldPosition, aim.Unit
	local state = {
		owner = player,
		tool = tool,
		character = character,
		connections = {},
	}
	Active[player] = state
	tool:SetAttribute("InUse", true)
	tool:SetAttribute("InCooldown", true)
	local beam = tool:FindFirstChild("Rope")
	if beam and beam:IsA("Beam") then beam.Enabled = true end
	local bolt = tool:FindFirstChild("Bolt", true)
	if bolt and bolt:IsA("BasePart") then bolt.Transparency = 1 end
	PlaySound(tool:FindFirstChild("Handle"), sound("Fire"))
	state.connections.ownerDied = humanoid.Died:Connect(function() disconnectRope(player, true) end)
	state.connections.ownerBlasted = humanoid:GetAttributeChangedSignal("BombBlastRevision"):Connect(function()
		if Active[player] == state then disconnectRope(player, true) end
	end)
	state.connections.toolUnequipped = tool.Unequipped:Connect(function()
		disconnectRope(player)
		-- The Backpack owns tool selection. A delayed UnequipTools here could
		-- put away a newly re-equipped gun after this old rope was released.
	end)
	state.connections.toolDestroyed = tool.Destroying:Connect(function() disconnectRope(player, true) end)
	local hitbox = createHitbox(state, origin, direction)
	local boltColor = cosmeticColors[player:GetAttribute("GrappleGunColor")]
	if boltColor then
		hitbox:SetAttribute("BoltColor", boltColor)
	elseif bolt and bolt:IsA("BasePart") then
		hitbox:SetAttribute("BoltColor", bolt.Color)
	end
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
			decayStruggle(state, now)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectRope(player, true)
	local owner = GrappleOwners[player.UserId]
	if owner then disconnectRope(owner, true) end
	for _, state in pairs(physicsSessions) do
		if state.detached and (state.owner == player or state.victimPlayer == player) then
			finishVictimHandoff(state, player)
		end
	end
	WallMode[player], lastFire[player], cooldownUntil[player] = nil, nil, nil
	lastModeToggle[player] = nil
end)

local function watchPlayer(player: Player)
	local watched = setmetatable({}, {__mode = "k"})
	local function refreshCosmetics()
		applyCosmetics(player, findInventoryTool(player, Config.toolName))
		local bomb = findInventoryTool(player, Config.bombToolName)
		local handle = bomb and bomb:FindFirstChild("Handle")
		local color = cosmeticColors[player:GetAttribute("BombColor")]
		if color and handle and handle:IsA("BasePart") then handle.Color = color end
	end
	for _, key in ipairs({"GrappleGunColor", "GrappleRopeColor", "BombColor"}) do
		player:GetAttributeChangedSignal(key):Connect(refreshCosmetics)
	end
	local function watchInventory(container)
		if watched[container] then return end
		watched[container] = true
		container.ChildAdded:Connect(function(tool) ToolSetup.Prepare(tool, true) refreshCosmetics() end)
		for _, tool in ipairs(container:GetChildren()) do ToolSetup.Prepare(tool, true) end
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchInventory(child) end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchInventory(backpack) end
	player.CharacterAdded:Connect(watchInventory)
	if player.Character then watchInventory(player.Character) end
	player.CharacterRemoving:Connect(function(character)
		disconnectRope(player, true)
		local owner = GrappleOwners[player.UserId]
		if owner then disconnectRope(owner, true) end
		for _, state in pairs(physicsSessions) do
			if state.detached and (state.character == character or state.victimCharacter == character) then
				finishVictimHandoff(state, state.victimCharacter == character and player or nil)
			end
		end
	end)
end

-- Prepare the template too, before a Backpack clone can start its old scripts.
local starterPack = game:GetService("StarterPack")
starterPack.ChildAdded:Connect(function(tool) ToolSetup.Prepare(tool, true) end)
for _, tool in ipairs(starterPack:GetChildren()) do ToolSetup.Prepare(tool, true) end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

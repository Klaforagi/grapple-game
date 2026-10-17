-- Server validates grapples; the grappler simulates the connected mechanism.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Upgrades = require(ReplicatedStorage.Modules:WaitForChild("UpgradeCatalog"))
local Cosmetics = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Ragdoll = require(ReplicatedStorage.Modules:WaitForChild("RagdollService"))
local ToolSetup = require(ReplicatedStorage.Modules:WaitForChild("GrappleToolSetup"))
local Sounds = ReplicatedStorage:FindFirstChild("Sounds")
local PlaySound = require(ReplicatedStorage.Modules:WaitForChild("PlaySound"))
local KillCredit = require(ReplicatedStorage.Modules:WaitForChild("KillCredit"))
local function sound(name)
	return Sounds and Sounds:FindFirstChild(name)
end

local FIRE_INTERVAL = 0.05
local LENGTH_INTERVAL = Config.ropeReelInterval or 1 / 15
-- Noclip flight is moved by script, so a normal body loses a tug-of-war with a
-- ragdoll on the rope. A heavier grappler and a lighter victim let the rope
-- lift the other person. Density 0.7 is a normal character part.
local NOCLIP_BODY_DENSITY = 10
local NOCLIP_VICTIM_DENSITY = 0.1
local minRopeLength = Config.minRopeLength or Config.MinRopeLength or 0.1
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
local escaping: {[Player]: boolean} = {}
local pendingEscape: {[Player]: boolean} = {}
local seenEscape: {[string]: boolean} = {}
local pendingEscapeKills: {[number]: {targetId: number, expiresAt: number}} = {}
local seenEscapeKills: {[string]: boolean} = {}
local wallOwnership = {}
local lastFire: {[Player]: number} = {}
local cooldownUntil: {[Player]: number} = {}
local function startCooldown(player, tool, duration)
	local deadline = math.max(cooldownUntil[player] or 0, os.clock() + duration)
	cooldownUntil[player] = deadline
	tool:SetAttribute("InCooldown", true)
	task.delay(math.max(0, deadline - os.clock()), function()
		if cooldownUntil[player] == deadline and tool.Parent then
			tool:SetAttribute("InCooldown", false)
		end
	end)
end
local lastModeToggle: {[Player]: number} = {}
local preparedTools = setmetatable({}, {__mode = "k"})
-- Includes detached victims awaiting handoff. Identity guards invalidate old timers.
local physicsSessions = {}
local nextPhysicsSession = 0
local Palettes = require(ReplicatedStorage:WaitForChild("ItemColors"))
local cosmeticColors = Palettes.Gun
local defaultGunMaterials = setmetatable({}, {__mode = "k"})
local defaultGunMaterialVariants = setmetatable({}, {__mode = "k"})
local defaultGunTransparency = setmetatable({}, {__mode = "k"})
local CHAIN_TEXTURE = "rbxassetid://18383765441"
local ROPE_STYLE_ATTRIBUTE = "DefaultRopeStyleSaved"
local ropeTransparencyDefaults = setmetatable({}, {__mode = "k"})

local function defaultRopeBeamStyle(beam: Beam)
	local template = StarterPack:FindFirstChild(Config.toolName)
	local templateBeam = template and template:FindFirstChild("Rope", true)
	local source = templateBeam and templateBeam:IsA("Beam") and templateBeam or beam
	local transparency = ropeTransparencyDefaults[beam]
	if not transparency then
		local saved = beam:GetAttribute("DefaultRopeTransparency")
		transparency = source ~= beam and source.Transparency
			or saved ~= nil and NumberSequence.new(saved) or beam.Transparency
		ropeTransparencyDefaults[beam] = transparency
		beam:SetAttribute("DefaultRopeTransparency", transparency.Keypoints[1].Value)
	end
	if beam:GetAttribute(ROPE_STYLE_ATTRIBUTE) then
		local brightness = beam:GetAttribute("DefaultRopeBrightness")
		if brightness == nil then
			brightness = source.Brightness
			beam:SetAttribute("DefaultRopeBrightness", brightness)
		end
		return {
			Texture = beam:GetAttribute("DefaultRopeTexture"),
			TextureLength = beam:GetAttribute("DefaultRopeTextureLength"),
			Width0 = beam:GetAttribute("DefaultRopeWidth0"),
			Width1 = beam:GetAttribute("DefaultRopeWidth1"),
			Brightness = brightness,
			Transparency = transparency,
		}
	end
	-- A live tool may already have Chain's settings after a script restart. The
	-- StarterPack tool is the untouched source for its regular beam appearance.
	local defaults
	if source.Texture == CHAIN_TEXTURE then
		-- Also handle tools supplied without a pristine StarterPack template.
		defaults = {Texture = "", TextureLength = 1, Width0 = 0.1, Width1 = 0.1, Brightness = source.Brightness}
	else
		defaults = {
			Texture = source.Texture, TextureLength = source.TextureLength,
			Width0 = source.Width0, Width1 = source.Width1, Brightness = source.Brightness,
		}
	end
	beam:SetAttribute("DefaultRopeTexture", defaults.Texture)
	beam:SetAttribute("DefaultRopeTextureLength", defaults.TextureLength)
	beam:SetAttribute("DefaultRopeWidth0", defaults.Width0)
	beam:SetAttribute("DefaultRopeWidth1", defaults.Width1)
	beam:SetAttribute("DefaultRopeBrightness", defaults.Brightness)
	beam:SetAttribute(ROPE_STYLE_ATTRIBUTE, true)
	defaults.Transparency = transparency
	return defaults
end

local function applyRopeBeamStyle(beam: Beam, ropeName: string?)
	local defaults = defaultRopeBeamStyle(beam)
	local neon = Palettes.NeonRopes[ropeName] ~= nil
	beam.Brightness = neon and 10 or ropeName == "Gold" and 1.25 or defaults.Brightness
	beam.Transparency = defaults.Transparency
	if ropeName == "Chain" then
		beam.Texture = CHAIN_TEXTURE
		beam.TextureLength = 6
		beam.Width0, beam.Width1 = 4, 4
	else
		beam.Texture = defaults.Texture
		beam.TextureLength = defaults.TextureLength
		beam.Width0, beam.Width1 = defaults.Width0, defaults.Width1
	end
end

local function applyCosmetics(player: Player, tool: Tool?)
	if not tool then return end
	local gunName = player:GetAttribute("GrappleGunColor")
	local gunColor = Palettes.NeonGunPartColors[gunName] or cosmeticColors[gunName]
	local rareGun = Palettes.RareGuns[gunName]
	local goldGun = gunName == "Gold"
	local neonGun = Palettes.NeonGuns[gunName] ~= nil
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			if not defaultGunMaterials[part] then defaultGunMaterials[part] = part.Material end
			if defaultGunMaterialVariants[part] == nil then defaultGunMaterialVariants[part] = part.MaterialVariant or "" end
			if defaultGunTransparency[part] == nil then
				defaultGunTransparency[part] = part:GetAttribute("GrappleBoltVisibleTransparency") or part.Transparency
			end
			part.Material = rareGun and Enum.Material[rareGun.Material]
				or neonGun and Enum.Material.Neon or defaultGunMaterials[part]
			part.MaterialVariant = rareGun and "" or defaultGunMaterialVariants[part]
			local visibleTransparency = rareGun and rareGun.Transparency or defaultGunTransparency[part]
			local activeState = Active[player]
			if part.Name == "Bolt" and activeState and activeState.boltTransparency ~= nil then
				activeState.boltTransparency = visibleTransparency
				part:SetAttribute("GrappleBoltVisibleTransparency", visibleTransparency)
				if activeState.hitbox then activeState.hitbox:SetAttribute("BoltVisibleTransparency", visibleTransparency) end
				part.Transparency = 1
			else
				part.Transparency = visibleTransparency
			end
			part:SetAttribute("RainbowPart", gunName == "Rainbow" or goldGun)
			part:SetAttribute("RainbowPalette", goldGun and "Gold" or nil)
			if gunColor then part:SetAttribute("SolidPartColor", gunColor) end
		end
	end
	if gunColor then
		for _, instance in ipairs(tool:GetDescendants()) do
			if instance:IsA("BasePart") then instance.Color = gunColor end
		end
		local bolt = tool:FindFirstChild("Bolt", true)
		if bolt and bolt:IsA("BasePart") then bolt.Color = gunColor end
	end
	local ropeName = player:GetAttribute("GrappleRopeColor")
	local ropeColor = Palettes.Rope[ropeName]
	local beam = tool:FindFirstChild("Rope")
	local rainbow = ropeName == "Rainbow" or ropeName == "Gold"
	local goldRope = ropeName == "Gold"
	if beam and beam:IsA("Beam") then
		applyRopeBeamStyle(beam, ropeName)
		beam:SetAttribute("RainbowRope", rainbow)
		beam:SetAttribute("RainbowPalette", goldRope and "Gold" or nil)
		if ropeColor then beam:SetAttribute("SolidRopeColor", ropeColor) end
	end
	local activeState = Active[player]
	local activeVisual = activeState and activeState.rope and activeState.rope:FindFirstChild("RopeVisual")
	if activeVisual then
		if beam and beam:IsA("Beam") then
			for _, property in ipairs({"Texture", "TextureLength", "Width0", "Width1", "Brightness", "Transparency"}) do
				activeVisual[property] = beam[property]
			end
		end
		activeVisual:SetAttribute("RainbowRope", rainbow)
		activeVisual:SetAttribute("RainbowPalette", goldRope and "Gold" or nil)
		if ropeColor then activeVisual:SetAttribute("SolidRopeColor", ropeColor) end
	end
	if ropeColor and beam and beam:IsA("Beam") then beam.Color = ColorSequence.new(ropeColor) end
	local state = Active[player]
	if ropeColor and state and state.rope then
		state.rope.Color = BrickColor.new(ropeColor)
		local visual = state.rope:FindFirstChild("RopeVisual")
		if visual then visual.Color = ColorSequence.new(ropeColor) end
	end
end

local function findInventoryTool(player: Player, name: string): Tool?
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = (character and character:FindFirstChild(name)) or (backpack and backpack:FindFirstChild(name))
	return tool and tool:IsA("Tool") and tool or nil
end

local function publishWallMode(player: Player)
	local enabled = WallMode[player] == true
	for _, container in ipairs({player.Character, player:FindFirstChildOfClass("Backpack")}) do
		if container then
			local tool = container:FindFirstChild(Config.toolName)
			if tool and tool:IsA("Tool") then tool:SetAttribute("WallMode", enabled) end
		end
	end
end

local function clearWallMode(player: Player)
	WallMode[player] = false
	publishWallMode(player)
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

local function setDensity(part, density)
	local props = part.CurrentPhysicalProperties
	if props == nil or type(density) ~= "number" then return end
	local friction = props.Friction
	if type(friction) ~= "number" then friction = 0.3 end
	local elasticity = props.Elasticity
	local frictionWeight = props.FrictionWeight
	local elasticityWeight = props.ElasticityWeight
	if type(elasticity) ~= "number" then elasticity = 0.5 end
	if type(frictionWeight) ~= "number" then frictionWeight = 1 end
	if type(elasticityWeight) ~= "number" then elasticityWeight = 1 end
	part.CustomPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)
end

local function bodyParts(character)
	local parts = {}
	if not character then return parts end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then parts[#parts + 1] = part end
	end
	return parts
end

-- [player] = {[part] = original density}. Present only while noclip mass is applied.
local heavyMass = {}

local function applyHeavy(player)
	local saved = heavyMass[player]
	if not saved then
		saved = {}
		heavyMass[player] = saved
	end
	for _, part in ipairs(bodyParts(player.Character)) do
		local props = part.CurrentPhysicalProperties
		if saved[part] == nil and props then saved[part] = props.Density end
		setDensity(part, NOCLIP_BODY_DENSITY)
	end
end

local function restoreHeavy(player)
	local saved = heavyMass[player]
	heavyMass[player] = nil
	if not saved then return end
	for part, density in pairs(saved) do
		if part.Parent and type(density) == "number" then setDensity(part, density) end
	end
end

local function lightenVictim(state)
	local saved = state.victimMass
	if not saved then
		saved = {}
		state.victimMass = saved
	end
	for _, part in ipairs(bodyParts(state.victimCharacter)) do
		local props = part.CurrentPhysicalProperties
		if saved[part] == nil and props then saved[part] = props.Density end
		setDensity(part, NOCLIP_VICTIM_DENSITY)
	end
end

local function restoreVictimMass(state)
	local saved = state.victimMass
	state.victimMass = nil
	if not saved then return end
	for part, density in pairs(saved) do
		if part.Parent and type(density) == "number" then setDensity(part, density) end
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
		local captive = humanoid:GetAttribute("CapsuleLocked") == true
		-- The capsule already owns this body. Handing simulation back, or
		-- rebuilding the ragdoll, puts the tilted pose on the server again.
		if not captive then
			if victim and victim ~= departingPlayer and victim.Parent == Players and victim.Character == character then
				Ragdoll.RefreshOwnership(humanoid)
			else
				restoreAutomaticNetworkOwnership(character)
			end
		end
		humanoid:SetAttribute("GrapplePhysicsLocked", nil)
		humanoid:SetAttribute("GrapplePhysicsSession", nil)
		if not captive and humanoid:HasTag("Ragdoll") then Ragdoll.Set(humanoid, true) end
		if not captive and state.appliedRagdoll and humanoid.Health > 0
			and os.clock() >= (humanoid:GetAttribute("BombRagdollUntil") or 0)
			and os.clock() >= (humanoid:GetAttribute("ForcedRagdollUntil") or 0) then
			-- Set before removing the tag so its observer cannot run pose recovery.
			Ragdoll.Set(humanoid, false, true)
			if not humanoid:GetAttribute("Ragdolled") then humanoid:RemoveTag("Ragdoll") end
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
	restoreVictimMass(state)

	for _, connection in pairs(state.connections) do connection:Disconnect() end
	if state.rope then state.rope:Destroy() end
	local wallRoot = state.wallRoot
	if wallRoot and wallOwnership[wallRoot] == state then
		wallOwnership[wallRoot] = nil
		if wallRoot.Parent then
			wallRoot:SetAttribute("WallGrappleOwner", nil)
			pcall(function()
				if not wallRoot:CanSetNetworkOwnership() then return end
				local previous = state.wallPreviousOwner
				if state.wallWasAutomatic or (previous and previous.Parent ~= Players) then
					wallRoot:SetNetworkOwnershipAuto()
				else
					wallRoot:SetNetworkOwner(previous)
				end
			end)
		end
	end
	if state.ownerAttachment then state.ownerAttachment:Destroy() end
	if state.impactAttachment then state.impactAttachment:Destroy() end
	if state.hitbox then state.hitbox:Destroy() end
	if state.beam and state.beam.Parent then
		state.beam.Attachment1 = state.originalBeamAttachment
		state.beam.Enabled = false
	end

	local victimHumanoid: Humanoid? = state.victimHumanoid
	if victimHumanoid then
		KillCredit.NoteRelease(victimHumanoid, state.owner.UserId, os.clock())
	end
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
					and not victimHumanoid:GetAttribute("CapsuleLocked")
					and physicsSessions[state.victimCharacter] == nil
					and os.clock() >= (victimHumanoid:GetAttribute("BombRagdollUntil") or 0) then
					Ragdoll.Set(victimHumanoid, false, true)
					if not victimHumanoid:GetAttribute("Ragdolled") then victimHumanoid:RemoveTag("Ragdoll") end
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
			local cooldown = preserveVictimMomentum and state.victimHumanoid and 1.5 or (Config.GrappleCooldown or 0.1)
			startCooldown(player, tool, cooldown)
		else
			cooldownUntil[player] = nil
			tool:SetAttribute("InCooldown", false)
		end
		local bolt = tool:FindFirstChild("Bolt", true)
		if bolt and bolt:IsA("BasePart") then
			bolt.Transparency = state.boltTransparency or 0
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
	rope.Visible = false
	rope.Thickness = 0.1
	rope.Color = ropeColorFromTool(state.tool)
	rope.Parent = impactAttachment.Parent
	local visual = Instance.new("Beam")
	visual.Name = "RopeVisual"
	visual.Attachment0, visual.Attachment1 = firePoint, impactAttachment
	visual.Width0, visual.Width1 = rope.Thickness, rope.Thickness
	visual.FaceCamera = true
	visual.Color = ColorSequence.new(Palettes.Rope[state.owner:GetAttribute("GrappleRopeColor")]
		or Color3.fromRGB(0, 0, 0))
	local source = state.tool and state.tool:FindFirstChild("Rope")
	if source and source:IsA("Beam") then
		for _, property in ipairs({"Color", "Transparency", "LightEmission", "LightInfluence",
			"Brightness", "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Width0", "Width1"}) do
			visual[property] = source[property]
		end
	end
	visual.Enabled = true
	visual.Segments = 24
	local ropeName = state.owner:GetAttribute("GrappleRopeColor")
	visual:SetAttribute("RainbowRope", ropeName == "Rainbow" or ropeName == "Gold")
	visual:SetAttribute("RainbowPalette", ropeName == "Gold" and "Gold" or nil)
	visual.Parent = rope
	state.rope = rope
	state.impactAttachment = impactAttachment
	return rope
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
		if not state.wallMode then disconnectRope(state.owner) return end
		local assembly = hit.AssemblyRootPart or hit
		if not assembly.Anchored then
			-- A physical assembly can only have one simulator. A new grapple
			-- replaces the previous wall tether rather than fighting its owner.
			local previous = wallOwnership[assembly]
			if previous and Active[previous.owner] == previous then disconnectRope(previous.owner) end
			pcall(function()
				if not assembly:CanSetNetworkOwnership() then return end
				state.wallWasAutomatic = assembly:GetNetworkOwnershipAuto()
				state.wallPreviousOwner = assembly:GetNetworkOwner()
				assembly:SetNetworkOwner(state.owner)
				state.wallRoot = assembly
				wallOwnership[assembly] = state
				assembly:SetAttribute("WallGrappleOwner", state.owner.UserId)
			end)
		end
		local attachment = createImpactAttachment(state.owner, hit, position)
		-- Sounds parented to a large part play from its center. The impact
		-- attachment stays at the actual bolt landing point as the part moves.
		PlaySound(attachment, sound("HitWall"))
		-- Wall ropes originate at the gun itself. FirePoint is part of the tool
		-- rig, so do not register it for session cleanup.
		local rope = makeRope(state, firePoint, attachment, (firePoint.WorldPosition - position).Magnitude)
		rope:SetAttribute("WallGrapple", true)
		state.tool:SetAttribute("HasGrappled", true)
		Remotes.GrappledWall:FireClient(state.owner, attachment, rope, rope:FindFirstChild("RopeVisual"))
		return
	end

	-- Wall mode never calls this branch. A character that slips through still
	-- must not become a player tether or turn the mode off.
	if state.wallMode then return end
	local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
	if victimPlayer == state.owner or hitHumanoid.Health <= 0 then disconnectRope(state.owner) return end
	-- Spawn shield and the paid escape shield are both ForceFields.
	if hitHumanoid:GetAttribute("CapsuleLocked") or hitModel:FindFirstChildOfClass("ForceField") then
		disconnectRope(state.owner)
		return
	end
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
	-- A catch inside the reel minimum used to store that shorter distance and
	-- replace the 4-stud floor. Slack the rope out to the floor instead.
	local separation = (ownerRoot.Position - attachmentPart.Position).Magnitude
	local rope = makeRope(state, ownerAttachment, attachment, math.max(separation, Config.playerMinDragDistance or 4))
	-- Both modes use a fixed maximum separation with no winch motor.
	rope:SetAttribute("PlayerGrapple", true)
	state.releaseAllowedAt = os.clock() + (Config.playerReleaseCooldown or 0.75)
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
	local grapplerName = state.owner.DisplayName
	if type(grapplerName) ~= "string" or grapplerName == "" then grapplerName = state.owner.Name end
	KillCredit.NoteAttach(hitHumanoid, state.owner.UserId, grapplerName)
	local tetherSeconds = Upgrades.HeldSeconds(state.owner, victimPlayer)
	state.tetherExpiresAt = os.clock() + tetherSeconds
	state.tetherDeadline = Workspace:GetServerTimeNow() + tetherSeconds
	if victimPlayer then
		Remotes.HasBeenGrappled:FireClient(victimPlayer, state.owner, state.tetherDeadline)
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
	Remotes.GrappledPlayer:FireClient(state.owner, hitModel, rope, state.tetherDeadline, victimPlayer and victimPlayer.Name or hitModel.Name)
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
	if state.boltTransparency ~= nil then
		hitbox:SetAttribute("BoltVisibleTransparency", state.boltTransparency)
	end
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
	local length = math.clamp(requestedLength, minimum, Upgrades.ShotDistance(player, state.wallMode))
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
	if not (player.GetAttribute and player:GetAttribute("TestPass_WallMode") == true) then return end
	-- Mode is chosen before the shot. Flight and an attached rope both count.
	if Active[player] then return end
	local now = os.clock()
	if now - (lastModeToggle[player] or -math.huge) < 0.15 then return end
	lastModeToggle[player] = now
	WallMode[player] = not (WallMode[player] == true)
	publishWallMode(player)
end)

local function setGrappleColor(player, target, colorName)
	if (target ~= "Gun" and target ~= "Rope" and target ~= "Bomb") or typeof(colorName) ~= "string" then
		return false
	end
	if colorName == "Teal" then colorName = "Mint" end
	if target == "Bomb" and colorName == "Lime" then colorName = "Green" end
	if not Palettes[target][colorName] and colorName ~= "Rainbow" then return false end
	if colorName == "Banana" and player:GetAttribute("Admin") ~= true then return false end
	if target == "Bomb" then
		player:SetAttribute("BombColor", colorName)
		local bomb = findInventoryTool(player, Config.bombToolName)
		local handle = bomb and bomb:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle:SetAttribute("RainbowPalette", colorName == "Gold" and "Gold" or "Bomb")
			handle:SetAttribute("RainbowPart", colorName == "Rainbow" or colorName == "Gold")
			if Palettes.Bomb[colorName] then
				handle.Color = Palettes.Bomb[colorName]
				handle:SetAttribute("SolidPartColor", Palettes.Bomb[colorName])
			end
		end
		return true
	end
	player:SetAttribute(target == "Gun" and "GrappleGunColor" or "GrappleRopeColor", colorName)
	applyCosmetics(player, findInventoryTool(player, Config.toolName))
	return true
end

Remotes.SetGrappleColor.OnServerEvent:Connect(function(player, target, colorName)
	if player:GetAttribute("CollectionLoaded") ~= true or not Cosmetics.Owns(player, target, colorName) then return end
	setGrappleColor(player, target, colorName)
end)

local adminColor = Instance.new("BindableFunction")
adminColor.Name = "AdminSetGrappleColor"
adminColor.OnInvoke = function(userId, target, colorName)
	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	if not player then return false end
	return setGrappleColor(player, target, colorName)
end
adminColor.Parent = ReplicatedStorage

local function raycastPastIgnoredParts(origin, direction, params, ignoreWindows)
	local ignored = params.FilterDescendantsInstances
	for _ = 1, 64 do
		local result = Workspace:Raycast(origin, direction, params)
		if not result or (result.Instance.Name ~= "InvisPart"
			and not (ignoreWindows and result.Instance.Name == "Window")) then return result end
		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end
	return nil
end

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
		wallMode = WallMode[player] == true,
	}
	Active[player] = state
	tool:SetAttribute("InUse", true)
	tool:SetAttribute("InCooldown", true)
	local beam = tool:FindFirstChild("Rope")
	if beam and beam:IsA("Beam") then beam.Enabled = true end
	local bolt = tool:FindFirstChild("Bolt", true)
	if bolt and bolt:IsA("BasePart") then
		state.boltTransparency = bolt.Transparency
		bolt:SetAttribute("GrappleBoltVisibleTransparency", state.boltTransparency)
		bolt.Transparency = 1
	end
	PlaySound(tool:FindFirstChild("Handle"), sound("Fire"))
	state.connections.ownerDied = humanoid.Died:Connect(function() disconnectRope(player, true) end)
	state.connections.ownerBlasted = humanoid:GetAttributeChangedSignal("BombBlastRevision"):Connect(function()
		if Active[player] == state and not state.victimHumanoid then disconnectRope(player, true) end
	end)
	state.connections.toolDestroyed = tool.Destroying:Connect(function() disconnectRope(player, true) end)
	local hitbox = createHitbox(state, origin, direction)
	local gunName = player:GetAttribute("GrappleGunColor")
	local boltColor = Palettes.NeonGunPartColors[gunName] or cosmeticColors[gunName]
	hitbox:SetAttribute("RainbowPart", gunName == "Rainbow" or gunName == "Gold")
	hitbox:SetAttribute("RainbowPalette", gunName == "Gold" and "Gold" or nil)
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
	local reach = Upgrades.ShotDistance(player, state.wallMode)
	local hookSpeed = Upgrades.HookSpeed(player, state.wallMode)
	local travelled, lastPosition, accumulator = 0, origin, 0
	while Active[player] == state and travelled < reach do
		accumulator += RunService.Heartbeat:Wait()
		if Active[player] ~= state then break end
		if accumulator < (1 / 30) then continue end
		local dt = math.min(accumulator, 0.1)
		accumulator = 0
		local nextTravelled = math.min(travelled + hookSpeed * dt, reach)
		local nextPosition = origin + direction * nextTravelled
		hitbox.CFrame = CFrame.new(nextPosition, nextPosition + direction)
		local hit, impactPosition = nil, nil
		if state.wallMode then
			-- Players and NPCs are not targets. Skip them and keep the ray going
			-- so a person standing in front of a wall does not eat the shot.
			local ignored = {character, tool, hitboxFolder}
			local seen = {}
			for _ = 1, 8 do
				rayParams.FilterDescendantsInstances = ignored
				local result = raycastPastIgnoredParts(lastPosition, nextPosition - lastPosition, rayParams)
				if not result or not result.Instance:IsA("BasePart") then break end
				local hitModel = characterFromPart(result.Instance)
				if not hitModel then
					hit, impactPosition = result.Instance, result.Position
					break
				end
				if seen[hitModel] then break end
				seen[hitModel] = true
				table.insert(ignored, hitModel)
			end
		else
			local segment = nextPosition - lastPosition
			local size = hitbox.Size
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(lastPosition + segment / 2, lastPosition + segment / 2 + direction), Vector3.new(size.X, size.Y, segment.Magnitude + size.Z), overlapParams)
			hit = findCharacterHit(parts, lastPosition, direction)
			impactPosition = hit and hit.Position or nil
			-- Overlap boxes see through solid walls; verify the selected target is visible.
			if hit then
				local obstruction = raycastPastIgnoredParts(lastPosition, impactPosition - lastPosition, rayParams, true)
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

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for owner, state in pairs(Active) do
		if state.rope then
			local a0, a1 = state.rope.Attachment0, state.rope.Attachment1
			if not a0 or not a0.Parent or not a1 or not a1.Parent then
				disconnectRope(owner)
				continue
			end
			if state.tetherExpiresAt and now >= state.tetherExpiresAt then disconnectRope(owner) end
		end
		if Active[owner] == state and state.victimCharacter then
			if owner:GetAttribute("Noclip") == true then
				lightenVictim(state)
			elseif state.victimMass then
				restoreVictimMass(state)
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Noclip") == true and player.Character then
			applyHeavy(player)
		elseif heavyMass[player] then
			restoreHeavy(player)
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
	lastModeToggle[player], escaping[player], pendingEscape[player] = nil, nil, nil
end)

local function tetherOwner(player: Player): Player?
	local owner = GrappleOwners[player.UserId]
	local state = owner and Active[owner]
	if state and state.victimPlayer == player then return owner end
	return nil
end

local function addShield(character: Model, seconds: number, name: string)
	local shield = Instance.new("ForceField")
	shield.Name = name
	shield.Parent = character
	task.delay(seconds, function()
		if shield.Parent then shield:Destroy() end
	end)
end

local function stripShields(model)
	if not model then return end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("ForceField") then child:Destroy() end
	end
end

local function isLiving(model): boolean
	if not model or not model.Parent then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The bubble is drawn from the model's Torso or UpperTorso. It has to be
-- parented to the living character after that part exists. The ragdoll corpse
-- stays in the world and must not keep or receive one.
local function grantSpawnShield(player: Player, hinted)
	local hintedAlive = isLiving(hinted)
	local currentAlive = isLiving(player.Character)
	local target = nil
	if hintedAlive and (player.Character == hinted or not currentAlive) then
		target = hinted
	elseif currentAlive then
		target = player.Character
	end
	if hinted and hinted ~= target then stripShields(hinted) end
	if player.Character and player.Character ~= target then stripShields(player.Character) end
	if not target or target:FindFirstChild("SpawnShield") then return end
	if not (target:FindFirstChild("UpperTorso", true) or target:FindFirstChild("Torso", true)) then return end
	local other = target:FindFirstChildOfClass("ForceField")
	if other then other:Destroy() end
	addShield(target, Config.spawnShieldSeconds or 8, "SpawnShield")
end

local shieldedLife = setmetatable({}, {__mode = "k"})
local function watchShield(player: Player, character: Model)
	if shieldedLife[character] then return end
	shieldedLife[character] = true
	local function bindHumanoid(humanoid)
		if not humanoid or not humanoid:IsA("Humanoid") or shieldedLife[humanoid] then return end
		shieldedLife[humanoid] = true
		local function onDeath()
			if humanoid.Health <= 0 then stripShields(character) end
		end
		humanoid.Died:Connect(onDeath)
		humanoid:GetPropertyChangedSignal("Health"):Connect(onDeath)
	end
	bindHumanoid(character:FindFirstChildOfClass("Humanoid"))
	character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then bindHumanoid(child) end
		if child.Name == "Torso" or child.Name == "UpperTorso" then
			task.defer(function() grantSpawnShield(player, character) end)
		end
	end)
end

local function releaseAndShield(player: Player)
	local owner = tetherOwner(player)
	if owner then disconnectRope(owner) end
	local character = player.Character
	if character then addShield(character, Config.escapeShieldSeconds or 6, "EscapeShield") end
end

local function grantEscape(userId, purchaseId)
	if type(userId) ~= "number" or type(purchaseId) ~= "string" or purchaseId == "" then return false end
	if seenEscape[purchaseId] then return true end
	local player = Players:GetPlayerByUserId(userId)
	if not player then return false end
	seenEscape[purchaseId] = true
	pendingEscape[player] = nil
	releaseAndShield(player)
	return true
end

local grantEscapeRemote = Instance.new("BindableFunction")
grantEscapeRemote.Name = "GrantEscapeRobux"
grantEscapeRemote.OnInvoke = grantEscape
grantEscapeRemote.Parent = ReplicatedStorage

local function grantEscapeKill(userId, purchaseId)
	if type(userId) ~= "number" or type(purchaseId) ~= "string" or purchaseId == "" then return false end
	if seenEscapeKills[purchaseId] then return true end
	local pending = pendingEscapeKills[userId]
	pendingEscapeKills[userId] = nil
	seenEscapeKills[purchaseId] = true
	if not pending or pending.expiresAt < os.clock() then return true end
	local target = Players:GetPlayerByUserId(pending.targetId)
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:SetAttribute("DeathEscapeKiller", userId)
		humanoid:SetAttribute("DeathCause", "EscapeKill")
		humanoid.Health = 0
	end
	return true
end

local grantEscapeKillRemote = Instance.new("BindableFunction")
grantEscapeKillRemote.Name = "GrantEscapeKillRobux"
grantEscapeKillRemote.OnInvoke = grantEscapeKill
grantEscapeKillRemote.Parent = ReplicatedStorage

local function escapeTether(player: Player, method)
	if not tetherOwner(player) then
		Remotes.EscapeTether:FireClient(player, false, "gone")
		return
	end
	if method == "robux" then
		local productId = Config.escapeRobuxProductId
		if type(productId) ~= "number" or productId <= 0 then
			Remotes.EscapeTether:FireClient(player, false, "unavailable")
			return
		end
		pendingEscape[player] = true
		Remotes.EscapeTether:FireClient(player, true, "prompt")
		return
	end
	if method == "kill" then
		local productId = Config.escapeKillRobuxProductId
		if type(productId) ~= "number" or productId <= 0 then
			Remotes.EscapeTether:FireClient(player, false, "unavailable")
			return
		end
		local owner = tetherOwner(player)
		if not owner then
			Remotes.EscapeTether:FireClient(player, false, "gone")
			return
		end
		pendingEscapeKills[player.UserId] = {targetId = owner.UserId, expiresAt = os.clock() + 120}
		Remotes.EscapeTether:FireClient(player, true, "killprompt")
		return
	end
	if escaping[player] then return end
	escaping[player] = true
	local useFreeEscape = ReplicatedStorage:FindFirstChild("UseFreeEscape")
	if useFreeEscape and player:GetAttribute("FreeEscapes") and player:GetAttribute("FreeEscapes") > 0 then
		local ok, used = pcall(function() return useFreeEscape:Invoke(player) end)
		if ok and used == true then
			if tetherOwner(player) then
				releaseAndShield(player)
				escaping[player] = nil
				Remotes.EscapeTether:FireClient(player, true, "free")
				return
			end
			escaping[player] = nil
			Remotes.EscapeTether:FireClient(player, false, "gone")
			return
		end
	end
	local cost = math.floor(tonumber(Config.escapeCoinCost) or 30)
	local spend = ReplicatedStorage:WaitForChild("SpendCoins")
	local ok, spent = pcall(function()
		return spend:Invoke(player.UserId, cost)
	end)
	if not ok or spent ~= true then
		escaping[player] = nil
		Remotes.EscapeTether:FireClient(player, false, "coins")
		return
	end
	if not tetherOwner(player) then
		local refund = ReplicatedStorage:FindFirstChild("RefundHeldCoins")
		if refund then pcall(function() refund:Invoke(player.UserId, cost) end) end
		escaping[player] = nil
		Remotes.EscapeTether:FireClient(player, false, "gone")
		return
	end
	releaseAndShield(player)
	escaping[player] = nil
	Remotes.EscapeTether:FireClient(player, true, "ok")
end

Remotes.EscapeTether.OnServerEvent:Connect(escapeTether)

local function watchPlayer(player: Player)
	local watched = setmetatable({}, {__mode = "k"})
	local watchedTools = setmetatable({}, {__mode = "k"})
	local function watchTool(tool)
		ToolSetup.Prepare(tool, true)
		if not tool:IsA("Tool") or tool.Name ~= Config.toolName or watchedTools[tool] then return end
		watchedTools[tool] = true
		tool:SetAttribute("WallMode", WallMode[player] == true)
		tool.Unequipped:Connect(function()
			if Active[player] and Active[player].tool == tool then disconnectRope(player) end
			startCooldown(player, tool, 1.5)
		end)
	end
	local function refreshCosmetics()
		applyCosmetics(player, findInventoryTool(player, Config.toolName))
		local bomb = findInventoryTool(player, Config.bombToolName)
		local handle = bomb and bomb:FindFirstChild("Handle")
		local color = Palettes.Bomb[player:GetAttribute("BombColor")]
		if handle and handle:IsA("BasePart") then
			handle:SetAttribute("RainbowPalette", player:GetAttribute("BombColor") == "Gold" and "Gold" or "Bomb")
			handle:SetAttribute("RainbowPart", player:GetAttribute("BombColor") == "Rainbow"
				or player:GetAttribute("BombColor") == "Gold")
			if color then handle:SetAttribute("SolidPartColor", color) end
		end
		if color and handle and handle:IsA("BasePart") then handle.Color = color end
	end
	for _, key in ipairs({"GrappleGunColor", "GrappleRopeColor", "BombColor"}) do
		player:GetAttributeChangedSignal(key):Connect(refreshCosmetics)
	end
	local function watchInventory(container)
		if watched[container] then return end
		watched[container] = true
		container.ChildAdded:Connect(function(tool) watchTool(tool) refreshCosmetics() end)
		for _, tool in ipairs(container:GetChildren()) do watchTool(tool) end
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchInventory(child) end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchInventory(backpack) end
	player.CharacterAdded:Connect(function(character)
		-- A new life starts with wall mode off. The backpack gun can survive death
		-- with the old attribute, so write it before the player equips again.
		clearWallMode(player)
		watchShield(player, character)
		task.defer(function()
			grantSpawnShield(player, character)
		end)
		watchInventory(character)
	end)
	if player.Character then
		watchShield(player, player.Character)
		watchInventory(player.Character)
	end
	if player.GetAttributeChangedSignal then
		player:GetAttributeChangedSignal("TestPass_WallMode"):Connect(function()
			if player:GetAttribute("TestPass_WallMode") ~= true then clearWallMode(player) end
		end)
		player:GetAttributeChangedSignal("TestPass_VIP"):Connect(function()
			if player:GetAttribute("TestPass_VIP") == true then return end
			for kind, name in pairs(Cosmetics.Defaults) do
				local key = Cosmetics.Attributes[kind]
				if player:GetAttribute(key) == "Gold" and not Cosmetics.Owns(player, kind, "Gold") then
					setGrappleColor(player, kind, name)
				end
			end
		end)
	end
	player.CharacterRemoving:Connect(function(character)
		stripShields(character)
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
StarterPack.ChildAdded:Connect(function(tool) ToolSetup.Prepare(tool, true) end)
for _, tool in ipairs(StarterPack:GetChildren()) do ToolSetup.Prepare(tool, true) end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

local function shieldBelongsOn(inst): boolean
	local model = inst.Parent
	if not model or not model:IsA("Model") then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The engine parents a SpawnLocation ForceField while the dead body can still
-- be the character. Keep Duration at 0 and drop any bubble that is not our
-- living-character shield.
local function claimSpawnShield(inst)
	if inst:IsA("SpawnLocation") then
		inst.Duration = 0
		return
	end
	if not inst:IsA("ForceField") then return end
	if inst.Name ~= "SpawnShield" and inst.Name ~= "EscapeShield" and inst.Name ~= "CapsuleRescueShield" then
		inst:Destroy()
		return
	end
	if not shieldBelongsOn(inst) then inst:Destroy() end
end
for _, inst in ipairs(Workspace:GetDescendants()) do claimSpawnShield(inst) end
Workspace.DescendantAdded:Connect(claimSpawnShield)

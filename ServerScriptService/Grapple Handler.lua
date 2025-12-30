-- This script runs on the SERVER
-- It handles all grapple logic: firing, hit detection, ropes,
-- grabbing players, wall grappling, struggle system, and cleanup

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Load grapple configuration (distances, cooldowns, debug mode, etc.)
local grappleConfig = require(ReplicatedStorage.GrappleConfig)

-- Shared folders / modules
local Remotes = ReplicatedStorage.Remotes
local FastCast = require(game.ReplicatedStorage.Modules.FastCastRedux)
local PartCache = require(game.ReplicatedStorage.Modules.PartCache)

-- Tracks players currently firing a grapple
-- PlayersFiring[playerName] = UserData table
local PlayersFiring = {}

-- Debug flag
local debugMode = grappleConfig.debugMode

-- Templates for ropes and visuals
local Templates = ReplicatedStorage.Templates

-- Sound helper module
local PlaySound = require(ReplicatedStorage.Modules.PlaySound)

-- Sound assets
local Sounds = ReplicatedStorage.Sounds

-- Tracks who is currently grappling a victim
-- victimPlayer.UserId -> grapplerPlayer
local GrappleOwners = {}

-- Per-player wall grapple toggle
-- true  = can grapple walls/objects
-- false = ignores walls/objects and only reacts to humanoids (shoots through walls)
local WallMode: {[Player]: boolean} = {}

-- Remote to toggle wall mode (press X on client)
if Remotes:FindFirstChild("ToggleWallMode") then
	Remotes.ToggleWallMode.OnServerEvent:Connect(function(plr: Player)
		WallMode[plr] = not (WallMode[plr] == true)

		-- optional: store it on the tool so you can debug/drive UI
		local char = plr.Character
		local tool = char and char:FindFirstChild(grappleConfig.toolName)
		if tool and tool:IsA("Tool") then
			tool:SetAttribute("WallMode", WallMode[plr])
		end
	end)
end

Players.PlayerRemoving:Connect(function(plr: Player)
	WallMode[plr] = nil
end)

----------------------------------------------------------------
-- DISCONNECT ROPE FUNCTION
----------------------------------------------------------------
-- Safely removes a grapple rope and resets the grappler state
-- noCooldown = true means we skip cooldown (used when stealing grapples)
local disconnectRope = function(plr : Player, noCooldown : boolean)
	local UserData = PlayersFiring[plr.Name]
	if not UserData then return end

	local victim = UserData.Victim

	-- Only apply cooldown if explicitly allowed
	if not noCooldown then
		UserData.Tool:SetAttribute("InCooldown", true)
		task.delay(grappleConfig.GrappleCooldown, function()
			if UserData.Tool then
				UserData.Tool:SetAttribute("InCooldown", false)
			end
		end)
	end
	
	-- Mark grapple as no longer active
	UserData.Tool:SetAttribute("HasGrappled", false)

	-- Destroy rope constraint if it exists
	if UserData.RopeConstraint then
		UserData.RopeConstraint:Destroy()
	end

	-- Restore humanoid movement if we grabbed someone
	if UserData.Humanoid then
		UserData.Humanoid:RemoveTag("Ragdoll")
		UserData.Humanoid.PlatformStand = false
		UserData.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	-- Disconnect all stored connections (events, remotes, etc.)
	for _, conn in pairs(UserData.Connections) do
		conn:Disconnect()
	end

	-- Clear firing state
	PlayersFiring[plr.Name] = nil

	-- Notify client that grapple ended
	Remotes.GrappledPlayer:FireClient(plr)
	if victim then
		Remotes.HasBeenGrappled:FireClient(victim)
	end
	
	-- Remove ownership if this player owned a victim
	for victimId, owner in pairs(GrappleOwners) do
		if owner == plr then
			GrappleOwners[victimId] = nil
		end
	end
	
	-- Restore bolt visibility
	local grapple : Tool = plr.Character:FindFirstChild(grappleConfig.toolName)
	if not grapple then return end
	
	PlaySound(grapple.Bolt,Sounds.Disconnect)
	grapple.Bolt.Transparency = 0
end
----------------------------------------------------------------
-- HIT HANDLER
----------------------------------------------------------------
-- Called when the grapple hitbox collides with something
local hitPart = function(plr:Player, firePoint : Attachment, hitbox : BasePart, hit:BasePart)
	-- Position where the hitbox collided
	local impactPos = hitbox.Position
	local m = hit:FindFirstAncestorOfClass("Model") or hit.Parent

	-- Create an attachment on the hit object
	-- This is where the rope will attach
	local impactAtt = Instance.new("Attachment")
	impactAtt.Name = plr.Name .. " Impact"
	impactAtt.Parent = hit
	impactAtt.WorldPosition = impactPos

	if debugMode then
		print("[Grapple] Direct-hit on (final):", hit:GetFullName())
	end

	-- Check if we hit a humanoid (player or NPC)
	local hum : Humanoid = m:FindFirstChildWhichIsA("Humanoid")
	if not hum then
		-- Hit a wall or object
		
		PlaySound(impactAtt, Sounds.HitWall)
		
		-- If wall grappling is disabled for THIS player, stop here
		if not (WallMode[plr] == true) then
			PlayersFiring[plr.Name] = nil
			return
		else

			-- Create rope for wall grappling
			local RopeConstraint = Templates.RopeConstraint:Clone()
			RopeConstraint.Parent = hit

			-- Set rope length based on distance
			RopeConstraint.Length = (firePoint.WorldPosition - impactAtt.WorldPosition).Magnitude

			-- Configure winch speed
			RopeConstraint.WinchSpeed = grappleConfig.ropeLengthSpeed * 3			
			local UserData = PlayersFiring[plr.Name]
			
			-- Listen once for rope length changes
			UserData.Connections.changeLengthConn =
				Remotes.ChangeLength.OnServerEvent:Once(function(player, length)
					if player == plr and RopeConstraint and RopeConstraint.Parent then
						local minL = grappleConfig.MinRopeLength or 0
						local maxL = grappleConfig.MaxRopeLength
							or grappleConfig.maxRopeLength
							or grappleConfig.MaxDistance
							or 200
						local newTarget = math.clamp(tonumber(length) or 0, minL, maxL)
						if RopeConstraint:FindFirstChild("WinchTarget") then
							RopeConstraint.WinchTarget.Value = newTarget
						end
					end
				end)

			-- Attach rope visuals
			local RopeVisual = RopeConstraint:FindFirstChild("RopeVisual")
			if RopeVisual then
				RopeConstraint.Attachment0 = firePoint
				RopeVisual.Attachment0 = firePoint
				RopeConstraint.Attachment1 = impactAtt
				RopeVisual.Attachment1 = impactAtt
			end
			
			-- Notify client of wall grapple
			Remotes.GrappledWall:FireClient(plr, impactAtt, RopeConstraint, RopeVisual, hitbox)
			UserData.Tool:SetAttribute("HasGrappled", true)

			UserData.RopeConstraint = RopeConstraint
			UserData.RopeVisual = RopeVisual
			return
		end
	end
	----------------------------------------------------------------
	-- PLAYER HIT LOGIC
	----------------------------------------------------------------
	PlaySound(impactAtt, Sounds.HitPerson)

	local UserData = PlayersFiring[plr.Name]
	if not UserData then
		if debugMode then
			print("[Grapple] No UserData for player", plr.Name)
		end
		return
	end

	local hitPlayer = Players:GetPlayerFromCharacter(m)
	
	-- If we hit another player
	if hitPlayer then
		-- Check if someone already owns this victim
		local previousGrappler = GrappleOwners[hitPlayer.UserId]

		if previousGrappler and previousGrappler ~= plr then
			if debugMode then
				print("[Grapple] Stealing victim from:", previousGrappler.Name)
			end

			-- Force old grappler to disconnect WITHOUT cooldown
			disconnectRope(previousGrappler, true)
		end

		-- Assign new grappler
		GrappleOwners[hitPlayer.UserId] = plr
				
		PlaySound(UserData.Tool.Handle, Sounds.Grapple)
		
		-- Create struggle remote dynamically
		local RS = game:GetService("ReplicatedStorage")
		local StruggleFolder = RS:FindFirstChild("Struggle") or Instance.new("Folder", RS)
		StruggleFolder.Name = "Struggle"

		-- Random ID generator
		local function randomId(len)
			local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
			local str = ""
			for i = 1, len do
				local idx = math.random(1, #chars)
				str = str .. chars:sub(idx, idx)
			end
			return str
		end

		local remoteName = randomId(12)
		local struggleRemote = Instance.new("RemoteEvent")
		struggleRemote.Name = remoteName
		struggleRemote.Parent = StruggleFolder

		UserData.struggleRemote = struggleRemote

		-- Send remote name to victim
		Remotes.HasBeenGrappled:FireClient(hitPlayer, plr, remoteName)

		if debugMode then
			print("Created struggle event:", struggleRemote.Name)
		end

		-- Listen for victim struggle success
		UserData.Connections = UserData.Connections or {}
		UserData.Connections.struggleConn =
			struggleRemote.OnServerEvent:Once(function(playerWhoFired)
				if playerWhoFired == hitPlayer then
					disconnectRope(plr)
					if struggleRemote and struggleRemote.Parent then
						struggleRemote:Destroy()
					end
				end
			end)
	end
	
	-- Unequips any tool the player has
	hum:UnequipTools()
	
	-- Apply ragdoll to victim
	UserData.Tool:SetAttribute("HasGrappled", true)
	hum:AddTag("Ragdoll")
	hum.PlatformStand = true
	hum:ChangeState(Enum.HumanoidStateType.Physics)

	-- Create rope constraint for player grapple
	local RopeConstraint = Templates.RopeConstraint:Clone()
	RopeConstraint.Parent = hit
	local dist = (firePoint.WorldPosition - impactAtt.WorldPosition).Magnitude

	RopeConstraint.Length = dist
	RopeConstraint.WinchTarget = dist  -- start neutral
	RopeConstraint.WinchSpeed = grappleConfig.ropeLengthSpeed

	-- Handle rope length changes
	UserData.Connections.changeLengthConn =
		Remotes.ChangeLength.OnServerEvent:Once(function(player, length)
			if player == plr and RopeConstraint and RopeConstraint.Parent then
				local minL = grappleConfig.MinRopeLength or 0
				local maxL = grappleConfig.MaxRopeLength
					or grappleConfig.maxRopeLength
					or grappleConfig.MaxDistance
					or 200
				local newTarget = math.clamp(tonumber(length) or 0, minL, maxL)
				if RopeConstraint:FindFirstChild("WinchTarget") then
					RopeConstraint.WinchTarget.Value = newTarget
				end
			end
		end)

	local RopeVisual = RopeConstraint:FindFirstChild("RopeVisual")
	if RopeVisual then
		RopeConstraint.Attachment0 = firePoint
		RopeVisual.Attachment0 = firePoint
		RopeConstraint.Attachment1 = impactAtt
		RopeVisual.Attachment1 = impactAtt
	end

	-- Notify grappler client
	Remotes.GrappledPlayer:FireClient(plr, m, RopeConstraint, RopeVisual, hitbox)

	UserData.RopeConstraint = RopeConstraint
	UserData.RopeVisual = RopeVisual
	UserData.Humanoid = hum
	
	UserData.Victim = hitPlayer
end
----------------------------------------------------------------
-- FIRE GRAPPLE EVENT
----------------------------------------------------------------
-- Called when the client fires the grapple
Remotes.FireGrapple.OnServerEvent:Connect(function(plr, hitPos, cameraPos)
	-- Basic validation
	if not hitPos then return end
	local char = plr.Character
	if not char then return end
	
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum or hum.Health <= 0 or hum:HasTag("Ragdoll") then
		if debugMode then
			print("Humanoid is either dead or ragdolled")
		end
		return
	end

	local grapple : Tool = char:FindFirstChild(grappleConfig.toolName)
	if not grapple then return end

	-- If already firing, cancel the shot and STOP (next click will fire)
	if grapple:GetAttribute("InUse") then
		PlayersFiring[plr.Name] = nil
		grapple:SetAttribute("InUse", false)
		return
	end

	-- Disconnect if already grappling
	if grapple:GetAttribute("HasGrappled") then
		if PlayersFiring[plr.Name] then
			disconnectRope(plr)
		end
		return
	end

	if grapple:GetAttribute("InCooldown") then return end

	-- Fire origin
	local FirePoint : Attachment = grapple:FindFirstChild("FirePoint", true)
	local visualOrigin =
		(FirePoint and FirePoint.WorldPosition)
		or (grapple.PrimaryPart and grapple.PrimaryPart.Position)
		or Vector3.new()

	local cameraOrigin = cameraPos or visualOrigin

	-- Clamp target distance so it won't go infinitely
	local requestedVec = hitPos - cameraOrigin
	local requestedDist = requestedVec.Magnitude
	if requestedDist == 0 then return end
	local requestedDir = requestedVec.Unit

	local maxAllowed = grappleConfig.maxRopeLength or requestedDist
	local finalDist = math.min(requestedDist, maxAllowed)
	local targetPos = cameraOrigin + requestedDir * finalDist

	-- Prepare states
	local Rope : Beam = grapple:FindFirstChild("Rope")
	grapple:SetAttribute("InCooldown", true)
	grapple:SetAttribute("InUse", true)
	if Rope then Rope.Enabled = true end

	PlayersFiring[plr.Name] = {
		Tool = grapple,
		Connections = {},
		struggleConn = {},
	}
	
	PlaySound(grapple.Handle, Sounds.Fire)

	-- Create moving hitbox
	local hitbox = Instance.new("Part")
	hitbox.Size = grappleConfig.HitboxSize or Vector3.new(1,1,1)
	hitbox.CanCollide = false
	hitbox.Anchored = true
	hitbox.Material = Enum.Material.Neon
	hitbox.Transparency = debugMode and 0 or 1
	hitbox.CastShadow = false
	hitbox.CFrame = CFrame.new(visualOrigin, visualOrigin + requestedDir)
	hitbox.Name = plr.Name.." Hitbox"
	hitbox.Parent = workspace.Hitbox
	-- Tell client to render visual bolt
	Remotes.FireGrapple:FireClient(plr, hitbox)

	local boltAtt = Instance.new("Attachment")
	boltAtt.Parent = hitbox
	Rope.Attachment1 = boltAtt
	-- Ignore self and tool in collision checks
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = {grapple, char}
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local travelled = 0
	-- Keep existing aim logic, but let the hook keep going to max distance
	local maxTravel =
		grappleConfig.maxRopeLength
		or grappleConfig.MaxRopeLength
		or grappleConfig.MaxDistance
		or 500

	local direction = (targetPos - visualOrigin).Unit
	local totalDist = maxTravel
	local hitDetected = false

	grapple.Bolt.Transparency = 1

	-- Move hitbox forward step-by-step
	while PlayersFiring[plr.Name] and not hitDetected and travelled < totalDist do
		local dt = RunService.Heartbeat:Wait()
		local step = (grappleConfig.HookSpeed or 80) * dt
		travelled = math.min(travelled + step, totalDist)

		local curPos = visualOrigin + direction * travelled
		hitbox.CFrame = CFrame.new(curPos, curPos + direction)

		local parts = workspace:GetPartBoundsInBox(hitbox.CFrame, hitbox.Size, overlapParams)

		local allowWalls = (WallMode[plr] == true)
		local chosenHit: BasePart? = nil

		for _, hit in ipairs(parts) do
			if hit ~= hitbox then
				-- IGNORE ACCESSORIES / TOOLS (hair, hats, etc.)
				if hit:FindFirstAncestorOfClass("Accessory") then
					continue
				end
				if hit:FindFirstAncestorOfClass("Tool") then
					continue
				end

				-- Only stop on humanoids when wall mode is OFF
				local model = hit:FindFirstAncestorOfClass("Model")
				local hum = model and model:FindFirstChildWhichIsA("Humanoid")

				if hum then
					chosenHit = hit
					break
				end

				-- If wall mode is ON, allow grappling walls/objects too
				if allowWalls then
					chosenHit = hit
					break
				end
			end
		end
		if chosenHit then
			hitDetected = true
			hitPart(plr, FirePoint, hitbox, chosenHit)
		end
	end
	-- Cleanup
	Remotes.FireGrapple:FireClient(plr, false)
	if hitbox then hitbox:Destroy() end

	if not grapple:GetAttribute("HasGrappled") then
		Rope.Attachment1 = grapple.Bolt.Attachment1
		grapple.Bolt.Transparency = 0
	end

	if Rope then Rope.Enabled = false end
	grapple:SetAttribute("InUse", false)

	task.delay(grappleConfig.GrappleCooldown or 2, function()
		grapple:SetAttribute("InCooldown", false)
	end)
end)

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local storage = game:GetService("ReplicatedStorage")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Remotes = require(storage.Modules:WaitForChild("GrappleRemotes"))
local Ragdoll = require(storage.Modules:WaitForChild("RagdollService"))
-- Disable the old GUI before StarterGui copies it into a player's PlayerGui.
local function retireGui(gui)
	if (gui.Name ~= Config.toolName and gui.Name ~= "Grapple Gun") or not gui:IsA("ScreenGui") then return end
	gui.Enabled = false
	local function disable(instance)
		if instance:IsA("LocalScript") then instance.Disabled = true end
	end
	for _, instance in ipairs(gui:GetDescendants()) do disable(instance) end
	gui.DescendantAdded:Connect(disable)
end
local starterGui = game:GetService("StarterGui")
for _, gui in ipairs(starterGui:GetChildren()) do retireGui(gui) end
starterGui.ChildAdded:Connect(retireGui)
local GROUP = "GrappleCharacters"
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, Config.playerCollisionsEnabled ~= false)

local pendingRespawns = {}
local fallStates = setmetatable({}, {__mode = "k"})
local function healthy(character)
	if not character or not character.Parent then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function ensureRespawn(player, deadCharacter)
	if pendingRespawns[player] then return end
	local ticket = {}
	pendingRespawns[player] = ticket
	local delay = (tonumber(Players.RespawnTime) or 5) + 1
	task.delay(delay, function()
		if pendingRespawns[player] ~= ticket then return end
		if player.Parent == Players and player.Character == deadCharacter and not healthy(deadCharacter) then
			-- Also handles a removed Humanoid/root and deaths that never emit Died.
			-- A failed load clears this ticket so the watchdog can retry.
			local ok, message = pcall(function() player:LoadCharacterAsync() end)
			if not ok then warn("[Respawn] Retrying failed character load: " .. tostring(message)) end
		end
		if pendingRespawns[player] == ticket then pendingRespawns[player] = nil end
	end)
end

local completedDeaths = setmetatable({}, {__mode = "k"})
local function finishDeath(player, character, humanoid)
	if completedDeaths[humanoid] then return end
	completedDeaths[humanoid] = true
	ensureRespawn(player, character)
	-- Physics ragdolls suspend automatic state transitions, including Dead.
	humanoid.EvaluateStateMachine = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	if not humanoid:GetAttribute("CapsuleLocked") then Ragdoll.BreakApart(humanoid) end
end

local function configure(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or player.Character ~= character then
		ensureRespawn(player, character)
		return
	end
	local function collision(instance)
		if instance:IsA("BasePart") then instance.CollisionGroup = GROUP end
	end
	for _, instance in ipairs(character:GetDescendants()) do collision(instance) end
	character.DescendantAdded:Connect(collision)
	character.ChildAdded:Connect(function(instance)
		if instance:IsA("Tool") and instance.Name ~= Config.bombToolName
			and humanoid:GetAttribute("GrapplePhysicsLocked") == true then
			local backpack = player:FindFirstChildOfClass("Backpack")
			if backpack then instance.Parent = backpack end
		end
	end)
	Ragdoll.Prepare(humanoid)
	fallStates[humanoid] = {character = character}
	if humanoid:HasTag("Ragdoll") then Ragdoll.Set(humanoid, true) end
	humanoid.Died:Connect(function()
		finishDeath(player, character, humanoid)
	end)
	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		if humanoid.Health <= 0 then finishDeath(player, character, humanoid) end
	end)
end
CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(humanoid)
	if humanoid:IsA("Humanoid") and humanoid.Parent then Ragdoll.Set(humanoid, true) end
end)
CollectionService:GetInstanceRemovedSignal("Ragdoll"):Connect(function(humanoid)
	-- Capsule settle removes the tag itself. The normal recovery plays a get-up
	-- and moves the root, which is the slant the captive must not enter with.
	if humanoid:IsA("Humanoid") and humanoid.Parent and humanoid.Health > 0
		and not humanoid:GetAttribute("CapsuleLocked") then
		Ragdoll.Set(humanoid, false)
	end
end)
local function playerAdded(player)
	player.CharacterAdded:Connect(function(character)
		pendingRespawns[player] = nil
		configure(player, character)
	end)
	if player.Character then task.spawn(configure, player, player.Character) end
end
Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(function(player) pendingRespawns[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
-- Defined with the fall helpers below. The toggle runs later, after that assignment.
local bodyLanded
Remotes.ToggleRagdoll.OnServerEvent:Connect(function(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("CapsuleLocked") then return end
	if humanoid:GetAttribute("ManualRagdoll") then
		humanoid:SetAttribute("ManualRagdoll", nil)
		-- If a knockdown still owns the body, retry when its lock expires.
		humanoid:SetAttribute("RagdollRecoveryRequested", true)
		Ragdoll.Set(humanoid, false)
		if not humanoid:GetAttribute("Ragdolled") then
			humanoid:RemoveTag("Ragdoll")
			humanoid:SetAttribute("RagdollRecoveryRequested", nil)
		end
	else
		humanoid:SetAttribute("RagdollRecoveryRequested", nil)
		humanoid:SetAttribute("ManualRagdoll", true)
		if not humanoid:GetAttribute("Ragdolled") then
			humanoid:SetAttribute("RagdollActivatedAt", os.clock())
		end
		humanoid:AddTag("Ragdoll")
		Ragdoll.Set(humanoid, true)
	end
end)
Remotes.EquipRagdollTool.OnServerEvent:Connect(function(player, toolName, shouldEquip)
	if type(toolName) ~= "string" or (toolName ~= Config.toolName and toolName ~= Config.bombToolName and toolName ~= Config.pushToolName) then return end
	if type(shouldEquip) ~= "boolean" then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0
		or humanoid:GetAttribute("Ragdolled") ~= true
		or (humanoid:GetAttribute("GrapplePhysicsLocked") == true and toolName ~= Config.bombToolName)
		or humanoid:GetAttribute("CapsuleLocked") == true then return end
	local equipped = character:FindFirstChild(toolName)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	if not shouldEquip then
		if equipped and equipped:IsA("Tool") then equipped.Parent = backpack end
		return
	end
	if equipped and equipped:IsA("Tool") then return end
	local tool = backpack:FindFirstChild(toolName)
	if not tool or not tool:IsA("Tool") then return end
	-- Transfer tools directly while the humanoid state machine is suspended.
	-- Do not call EquipTool/UnequipTools and then toggle again on a duplicate.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then child.Parent = backpack end
	end
	tool.Parent = character
end)
Remotes.ResetCharacter.OnServerEvent:Connect(function(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then humanoid.Health = 0 end
	ensureRespawn(player, player.Character)
end)

-- A ragdoll has no required neck, so Roblox cannot always infer death when
-- its loose parts start falling below FallenPartsDestroyHeight. Kill before
-- the parts are removed to keep void deaths and Reset on the normal respawn
-- path.
local VOID_KILL_PADDING = 25
local FALL_DESCEND_SPEED = 12 -- Downward studs/s. Slower motion is a hover, rope lower, or hop.
local FALL_FLOOR_SPEED = 8 -- Still falling this fast, FloorMaterial is the takeoff surface, not a landing.
local FALL_ARREST_TIME = 0.2 -- Holding below that speed this long cancels the fall.

local function fallDistanceRequired(humanoid)
	local minimum = Config.fallRagdollDistance or 30
	local gravity = Workspace.Gravity
	if type(gravity) ~= "number" or gravity <= 1 then gravity = 196.2 end
	local jumpHeight = tonumber(humanoid.JumpHeight) or 7.2
	if humanoid.UseJumpPower == true then
		local power = tonumber(humanoid.JumpPower) or 50
		jumpHeight = (power * power) / (2 * gravity)
	end
	-- Landing back on the same surface drops about one jump height.
	return math.max(minimum, jumpHeight + 12)
end

local function groundHit(origin, distance, params)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -distance, 0), params)
	if not hit or not hit.Position then return nil end
	local normalY = hit.Normal and hit.Normal.Y or 1
	if normalY <= 0.4 then return nil end
	return hit
end

-- Size.Y is the part's own axis. A sideways limb is wide in the world and short along Y,
-- so the landing test has to use the lowest corner, then fall back to an upright extent.
local function partBottom(part)
	local size = part.Size
	local position = part.Position
	local halfY = ((size and size.Y) or 0) * 0.5
	local cf = part.CFrame
	if typeof(cf) ~= "CFrame" or not cf.PointToWorldSpace or not size then
		return position.Y - halfY
	end
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local bottom = cf.Position.Y
	local samples = {
		cf:PointToWorldSpace(Vector3.new(-hx, -hy, -hz)), cf:PointToWorldSpace(Vector3.new(-hx, -hy, hz)),
		cf:PointToWorldSpace(Vector3.new(-hx, hy, -hz)), cf:PointToWorldSpace(Vector3.new(-hx, hy, hz)),
		cf:PointToWorldSpace(Vector3.new(hx, -hy, -hz)), cf:PointToWorldSpace(Vector3.new(hx, -hy, hz)),
		cf:PointToWorldSpace(Vector3.new(hx, hy, -hz)), cf:PointToWorldSpace(Vector3.new(hx, hy, hz)),
	}
	for _, point in ipairs(samples) do
		if point and point.Y < bottom then bottom = point.Y end
	end
	return bottom
end

local function bodyLowY(character, root)
	local low = partBottom(root)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then
			local bottom = partBottom(part)
			if bottom < low then low = bottom end
		end
	end
	return low
end

-- Once EvaluateStateMachine is off, FloorMaterial freezes on whatever it was at takeoff.
-- A fast fall also keeps that value until the humanoid notices, which is after the hit.
local function floorTrusted(humanoid, root)
	if humanoid.FloorMaterial == Enum.Material.Air then return false end
	if humanoid.EvaluateStateMachine == false then return false end
	if humanoid:HasTag("Ragdoll") or humanoid:GetAttribute("Ragdolled") == true then return false end
	local velocity = root.AssemblyLinearVelocity
	return not velocity or velocity.Y >= -FALL_FLOOR_SPEED
end

-- The root sits at the hips, and on a ragdoll it does not even collide.
-- A limb bottom touching the floor is the landing, not the root settling afterward.
bodyLanded = function(character, humanoid, root)
	if floorTrusted(humanoid, root) then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = true
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part ~= root then
			local bottom = partBottom(part)
			local hit = groundHit(Vector3.new(part.Position.X, bottom + 1.25, part.Position.Z), 2, params)
			if hit then
				local gap = bottom - hit.Position.Y
				if gap <= 0.75 and gap >= -2 then return true end
			end
		end
	end
	local foot = (root.Size.Y * 0.5) + (tonumber(humanoid.HipHeight) or 0)
	local hit = groundHit(root.Position + Vector3.new(0, 4, 0), 4 + foot + 4, params)
	if not hit then return false end
	local gap = root.Position.Y - hit.Position.Y
	return gap <= foot + 0.45 and gap >= -4
end

local function commitFallRagdoll(humanoid, state, now)
	local gun = humanoid.Parent and humanoid.Parent:FindFirstChild(Config.toolName)
	if gun and gun:GetAttribute("HasGrappled") then
		state.fallPeakY, state.arrestedAt = nil, nil
		return
	end
	if state.triggered then return end
	state.triggered = true
	state.fallPeakY, state.arrestedAt = nil, nil
	-- The current toggle, not the pose at impact, decides whether recovery is allowed.
	state.autoRecover = true
	local deadline = now + (Config.fallRagdollDuration or 3)
	humanoid:SetAttribute("FallRagdollUntil", deadline)
	humanoid:SetAttribute("RagdollActivatedAt", now)
	humanoid:AddTag("Ragdoll")
	Ragdoll.Set(humanoid, true)
end

-- The owning client hits the ground before this server's copy of the body does.
-- reportedPeak and duringFall are optional. Older callers send the landing height only.
Remotes.FallLanded.OnServerEvent:Connect(function(player, reportedY, reportedPeak, duringFall)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
	if humanoid:GetAttribute("CapsuleLocked") then return end
	local state = fallStates[humanoid]
	if not state or state.triggered or not state.fallPeakY then return end
	-- They ragdolled on the way down, even if they toggled back up before this arrived.
	if duringFall == true then state.wasRagdolled = true end
	local y = root.Position.Y
	local ragdolled = state.wasRagdolled == true or humanoid:HasTag("Ragdoll")
		or humanoid:GetAttribute("Ragdolled") == true
	if ragdolled then
		local low = bodyLowY(character, root)
		if low < y then y = low end
	end
	local slack = ragdolled and 80 or 25
	if type(reportedY) == "number" and reportedY == reportedY and reportedY < y and y - reportedY <= slack then
		y = reportedY
	end
	if type(reportedPeak) == "number" and reportedPeak == reportedPeak
		and reportedPeak > state.fallPeakY and reportedPeak - state.fallPeakY <= 40 then
		state.fallPeakY = reportedPeak
	end
	if state.fallPeakY - y < fallDistanceRequired(humanoid) then return end
	commitFallRagdoll(humanoid, state, os.clock())
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local destroyHeight = Workspace.FallenPartsDestroyHeight
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			if humanoid:GetAttribute("RagdollRecoveryRequested") then
				Ragdoll.Set(humanoid, false)
				if not humanoid:GetAttribute("Ragdolled") then
					humanoid:RemoveTag("Ragdoll")
					humanoid:SetAttribute("RagdollRecoveryRequested", nil)
				end
			end
			local state = fallStates[humanoid]
			if not state then
				state = {character = character}
				fallStates[humanoid] = state
			end
			local existingDeadline = humanoid:GetAttribute("FallRagdollUntil")
			if existingDeadline and now >= existingDeadline then
				local recover = state.autoRecover == true
				local blocked = recover and (humanoid:GetAttribute("GrapplePhysicsLocked")
					or humanoid:GetAttribute("CapsuleLocked")
					or now < (humanoid:GetAttribute("BombRagdollUntil") or 0)
					or now < (humanoid:GetAttribute("ForcedRagdollUntil") or 0))
				if not blocked then
					-- The lock is over either way. Only an unchosen fall stands them up.
					humanoid:SetAttribute("FallRagdollUntil", nil)
					state.triggered = nil
					if recover then
						state.autoRecover = nil
						Ragdoll.Set(humanoid, false, true)
						if not humanoid:GetAttribute("Ragdolled") then humanoid:RemoveTag("Ragdoll") end
					end
				end
			end
			-- Distance, not time in Freefall. A jump spends a long time in that state
			-- and the state often stays Freefall after the feet are already down.
			if humanoid:GetAttribute("CapsuleLocked") then
				state.fallPeakY, state.arrestedAt = nil, nil
			else
				local landed = bodyLanded(character, humanoid, root)
				local velocityY = root.AssemblyLinearVelocity.Y
				local ragdolled = humanoid:HasTag("Ragdoll") or humanoid:GetAttribute("Ragdolled") == true
				-- A floating root hides the drop. The body that actually fell is the lowest part.
				local height = root.Position.Y
				if ragdolled or state.wasRagdolled then
					local low = bodyLowY(character, root)
					if low < height then height = low end
				end
				if landed then
					if state.fallPeakY and not state.triggered
						and state.fallPeakY - height >= fallDistanceRequired(humanoid) then
						commitFallRagdoll(humanoid, state, now)
					else
						state.fallPeakY, state.arrestedAt = nil, nil
						state.wasRagdolled = nil
					end
				elseif not state.triggered then
					if ragdolled then state.wasRagdolled = true end
					if velocityY < -FALL_DESCEND_SPEED then
						state.arrestedAt = nil
						local sample = root.Position.Y
						state.fallPeakY = math.max(state.fallPeakY or sample, sample)
					elseif state.fallPeakY and (ragdolled or state.wasRagdolled) then
						-- The loose root stops, and standing back up zeroes vertical speed.
						-- Neither one is a new jump. This is still the same fall.
						state.arrestedAt = nil
					elseif velocityY > FALL_DESCEND_SPEED then
						state.fallPeakY, state.arrestedAt = nil, nil
						if not ragdolled then state.wasRagdolled = nil end
					else
						state.arrestedAt = state.arrestedAt or now
						if state.fallPeakY and not state.wasRagdolled and now - state.arrestedAt >= FALL_ARREST_TIME then
							state.fallPeakY = nil
						end
					end
				end
				if landed and not state.fallPeakY and not humanoid:GetAttribute("FallRagdollUntil") then
					state.triggered, state.autoRecover, state.wasRagdolled = nil, nil, nil
				end
			end
		end
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")
			and typeof(destroyHeight) == "number" and destroyHeight ~= -math.huge
			and root.Position.Y <= destroyHeight + VOID_KILL_PADDING then
			humanoid.Health = 0
		end
		if humanoid and humanoid.Health <= 0 then finishDeath(player, character, humanoid) end
		if not healthy(character) then ensureRespawn(player, character) end
	end
end)

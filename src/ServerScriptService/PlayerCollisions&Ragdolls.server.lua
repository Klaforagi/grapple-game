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
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

local pendingRespawns = {}
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
		if instance:IsA("Tool") and humanoid:HasTag("Ragdoll") then humanoid:UnequipTools() end
	end)
	Ragdoll.Prepare(humanoid)
	if humanoid:HasTag("Ragdoll") then Ragdoll.Set(humanoid, true) end
	humanoid.Died:Connect(function()
		ensureRespawn(player, character)
		humanoid:AddTag("Ragdoll")
		Ragdoll.Set(humanoid, true)

		-- Set may be a no-op if the player was already ragdolled before dying.
		-- Keep the camera's root on the floor in either case.
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then root.CanCollide = true end
	end)
end
CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(humanoid)
	if humanoid:IsA("Humanoid") and humanoid.Parent then Ragdoll.Set(humanoid, true) end
end)
CollectionService:GetInstanceRemovedSignal("Ragdoll"):Connect(function(humanoid)
	if humanoid:IsA("Humanoid") and humanoid.Parent and humanoid.Health > 0 then Ragdoll.Set(humanoid, false) end
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
Remotes.ToggleRagdoll.OnServerEvent:Connect(function(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("GrappledBy") then return end
	if humanoid:HasTag("Ragdoll") then
		local activatedAt = humanoid:GetAttribute("RagdollActivatedAt")
		if activatedAt and os.clock() - activatedAt < Config.ragdollToggle_Cooldown then return end
		humanoid:RemoveTag("Ragdoll")
		Ragdoll.Set(humanoid, false)
	else
		local recoveredAt = humanoid:GetAttribute("RagdollRecoveredAt")
		if recoveredAt and os.clock() - recoveredAt < Config.ragdollToggle_Cooldown then return end
		humanoid:SetAttribute("RagdollActivatedAt", os.clock())
		humanoid:AddTag("Ragdoll")
		Ragdoll.Set(humanoid, true)
	end
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
RunService.Heartbeat:Connect(function()
	local destroyHeight = Workspace.FallenPartsDestroyHeight
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")
			and typeof(destroyHeight) == "number" and destroyHeight ~= -math.huge
			and root.Position.Y <= destroyHeight + VOID_KILL_PADDING then
			humanoid.Health = 0
		end
		if not healthy(character) then ensureRespawn(player, character) end
	end
end)

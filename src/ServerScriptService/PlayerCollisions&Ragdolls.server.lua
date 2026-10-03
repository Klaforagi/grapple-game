-- Player collision groups and the server-side ragdoll lifecycle.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Requiring the service starts its tagged components.
require(ReplicatedStorage.Modules:WaitForChild("RagdollService"))

local PLAYER_GROUP = "p"
local groupExists = false
for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
	if group.name == PLAYER_GROUP then
		groupExists = true
		break
	end
end
if not groupExists then PhysicsService:RegisterCollisionGroup(PLAYER_GROUP) end
PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)

local ragdollDebounces: {[Player]: number} = {}
local collisionEnforcers: {[Humanoid]: RBXScriptConnection} = {}

local function assignCharacterCollisionGroup(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.CollisionGroup = PLAYER_GROUP end
	end
end

local function stopCollisionEnforcer(humanoid: Humanoid)
	local connection = collisionEnforcers[humanoid]
	if connection then connection:Disconnect() end
	collisionEnforcers[humanoid] = nil
end

local function setRagdollCollisions(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then return end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end
end

local function enforceRagdollCollisions(humanoid: Humanoid)
	stopCollisionEnforcer(humanoid)
	setRagdollCollisions(humanoid)
	local elapsed = 0
	collisionEnforcers[humanoid] = RunService.Heartbeat:Connect(function(dt)
		if not CollectionService:HasTag(humanoid, "Ragdoll") then
			stopCollisionEnforcer(humanoid)
			return
		end
		elapsed += dt
		if elapsed < 0.25 then return end
		elapsed = 0
		setRagdollCollisions(humanoid)
	end)
end

CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(instance)
	if not instance:IsA("Humanoid") then return end
	instance:UnequipTools()
	enforceRagdollCollisions(instance)
end)

CollectionService:GetInstanceRemovedSignal("Ragdoll"):Connect(function(instance)
	if instance:IsA("Humanoid") then stopCollisionEnforcer(instance) end
end)

local function configureCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	character:WaitForChild("HumanoidRootPart")
	humanoid:AddTag("Ragdollable")
	humanoid:AddTag("RagdollOnHumanoidDied")
	assignCharacterCollisionGroup(character)
	character.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then instance.CollisionGroup = PLAYER_GROUP end
	end)
end

local function configurePlayer(player: Player)
	player.CharacterAdded:Connect(configureCharacter)
	if player.Character then task.spawn(configureCharacter, player.Character) end
end

Players.PlayerAdded:Connect(configurePlayer)
for _, player in ipairs(Players:GetPlayers()) do configurePlayer(player) end

Remotes.ToggleRagdoll.OnServerEvent:Connect(function(player)
	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("GrappledBy") then return end
	local now = os.clock()
	if ragdollDebounces[player] and now - ragdollDebounces[player] < (Config.ragdollToggle_Cooldown or 3) then return end
	ragdollDebounces[player] = now
	if humanoid:HasTag("Ragdoll") then
		humanoid:RemoveTag("Ragdoll")
	else
		humanoid:AddTag("Ragdoll")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ragdollDebounces[player] = nil
	if player.Character then
		local humanoid = player.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then stopCollisionEnforcer(humanoid) end
	end
end)

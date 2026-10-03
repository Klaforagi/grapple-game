local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
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
local debounce = {}

local function configure(character)
	local humanoid = character:WaitForChild("Humanoid")
	character:WaitForChild("HumanoidRootPart")
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
	humanoid.Died:Connect(function() humanoid:AddTag("Ragdoll") end)
end
CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(humanoid)
	if humanoid:IsA("Humanoid") and humanoid.Parent then Ragdoll.Set(humanoid, true) end
end)
CollectionService:GetInstanceRemovedSignal("Ragdoll"):Connect(function(humanoid)
	if humanoid:IsA("Humanoid") and humanoid.Parent and humanoid.Health > 0 then Ragdoll.Set(humanoid, false) end
end)
local function playerAdded(player)
	player.CharacterAdded:Connect(configure)
	if player.Character then task.spawn(configure, player.Character) end
end
Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
Remotes.ToggleRagdoll.OnServerEvent:Connect(function(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("GrappledBy") then return end
	local now = os.clock()
	if debounce[player] and now - debounce[player] < Config.ragdollToggle_Cooldown then return end
	debounce[player] = now
	if humanoid:HasTag("Ragdoll") then humanoid:RemoveTag("Ragdoll") else humanoid:AddTag("Ragdoll") end
end)
Players.PlayerRemoving:Connect(function(player) debounce[player] = nil end)

local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local BombPhysics = require(Storage.Modules:WaitForChild("BombPhysics"))
local lastThrow = {}
local issued = setmetatable({}, {__mode = "k"})
local liveBombs = {}

local function sphere(name, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(0, 255, 255)
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return part
end

local function giveBomb(player, character)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then return end
	-- Existing grapple assets live in Studio's StarterPack. Add the bomb after
	-- those arrive; the client orders the two tools once per spawn as well.
	if not character:FindFirstChild(Config.toolName) then backpack:WaitForChild(Config.toolName, 10) end
	if player.Character ~= character or not character.Parent or issued[character] then return end
	issued[character] = true
	if backpack:FindFirstChild(Config.bombToolName) or character:FindFirstChild(Config.bombToolName) then return end
	local tool = Instance.new("Tool")
	tool.Name = Config.bombToolName
	tool.ToolTip = "Throw a bomb / 5 second fuse"
	tool.CanBeDropped = false
	tool:SetAttribute("BombTool", true)
	local handle = sphere("Handle", 1.2)
	handle.CanCollide, handle.CanTouch, handle.Massless = false, false, true
	handle.Parent = tool
	tool.Parent = backpack
end

local function knockback(character, humanoid, velocity)
	local assemblies = {}
	local grappledBy = humanoid:GetAttribute("GrappledBy")
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local assembly = part.AssemblyRootPart
			if assembly and not assembly.Anchored and not assemblies[assembly] then
				assemblies[assembly] = true
				local canOwn = assembly:CanSetNetworkOwnership()
				local previousOwner = canOwn and assembly:GetNetworkOwner() or nil
				if canOwn then assembly:SetNetworkOwner(nil) end
				assembly:ApplyImpulse(velocity * assembly.AssemblyMass)
				if canOwn then
					task.delay(0.2, function()
						if not assembly.Parent or humanoid.Parent ~= character then return end
						-- A new grapple/recovery may have changed ownership in the meantime.
						if humanoid:GetAttribute("GrappledBy") ~= grappledBy then return end
						if assembly:CanSetNetworkOwnership() and assembly:GetNetworkOwner() == nil then
							if previousOwner and previousOwner.Parent == Players then
								assembly:SetNetworkOwner(previousOwner)
							else
								assembly:SetNetworkOwnershipAuto()
							end
						end
					end)
				end
			end
		end
	end
end

local function explode(bomb, position)
	local radius = Config.bombRadius
	-- Visual only: do not use Explosion's joint-breaking damage/pressure.
	local flash = sphere("BombBlast", 1)
	flash.Anchored, flash.CanCollide, flash.CanTouch, flash.CanQuery = true, false, false, false
	flash.Position = position
	flash.Transparency = 0.35
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.35), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.4)
	-- Include NPC humanoids as well as players; apply only once per character.
	for _, humanoid in ipairs(workspace:GetDescendants()) do
		if humanoid:IsA("Humanoid") and humanoid.Health > 0 then
			local character = humanoid.Parent
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local velocity = BombPhysics.Knockback(root.Position - position, radius, Config.bombKnockback)
				if velocity.Magnitude > 0 then knockback(character, humanoid, velocity) end
			end
		end
	end
	bomb:Destroy()
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
	if not root or not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("Ragdolled") then return end
	if not tool or not tool:IsA("Tool") or not tool:GetAttribute("BombTool") then return end
	local now = os.clock()
	if now - (lastThrow[player] or -math.huge) < Config.bombCooldown then return end
	lastThrow[player] = now
	local aim = target - root.Position
	local direction = aim.Magnitude > 0.01 and aim.Unit or root.CFrame.LookVector
	local bomb = sphere("ThrownBomb", 1.2)
	bomb.Position = root.Position + Vector3.new(0, 1.5, 0)
	bomb.CustomPhysicalProperties = PhysicalProperties.new(1, 0.6, 0.25)
	bomb.Parent = workspace
	bomb:SetNetworkOwner(nil)
	-- Ignore the thrower's body briefly so the sphere can leave their hand.
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local ignore = Instance.new("NoCollisionConstraint")
			ignore.Part0, ignore.Part1 = bomb, part
			ignore.Parent = bomb
			Debris:AddItem(ignore, 0.3)
		end
	end
	bomb.AssemblyLinearVelocity = root.AssemblyLinearVelocity + direction * Config.bombThrowSpeed + Vector3.new(0, 12, 0)
	liveBombs[bomb] = {position = bomb.Position, detonatesAt = now + Config.bombFuse}
	Debris:AddItem(bomb, Config.bombFuse + 1)
end)

game:GetService("RunService").Heartbeat:Connect(function()
	local now = os.clock()
	for bomb, state in pairs(liveBombs) do
		if bomb.Parent then state.position = bomb.Position end
		if now >= state.detonatesAt then
			liveBombs[bomb] = nil
			explode(bomb, state.position)
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

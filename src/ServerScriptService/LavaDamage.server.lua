-- Server-authoritative damage for every BasePart named LavaBrick inside
-- Workspace.LavaBricks. Touch events catch short landings while jumping;
-- the overlap scan is retained for characters that begin inside a lava part.
-- A humanoid can take at most one lava tick per second, even when several
-- body parts or lava bricks overlap it at once.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DAMAGE = 30
local DAMAGE_COOLDOWN = 1
local OVERLAP_INTERVAL = 0.1

local lavaFolder = Workspace:WaitForChild("LavaBricks")
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = {Workspace}

local lavaParts: {[BasePart]: boolean} = {}
local nextDamageAt = setmetatable({}, {__mode = "k"})
local touchConnections: {[BasePart]: RBXScriptConnection} = {}

local function isLavaBrick(instance: Instance): boolean
	return instance:IsA("BasePart") and instance.Name == "LavaBrick"
end

local function register(instance: Instance)
	if isLavaBrick(instance) then lavaParts[instance :: BasePart] = true end
end

local function humanoidFromPart(part: BasePart): Humanoid?
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function damageHumanoid(humanoid: Humanoid, lavaBrick: BasePart)
	if humanoid.Health <= 0 then return end

	local now = os.clock()
	if now < (nextDamageAt[humanoid] or 0) then return end

	nextDamageAt[humanoid] = now + DAMAGE_COOLDOWN
	humanoid:TakeDamage(DAMAGE)

	local damageSound = lavaBrick:FindFirstChild("DamageSound")
	if damageSound and damageSound:IsA("Sound") then damageSound:Play() end
end

local function connectTouchDamage(lavaBrick: BasePart)
	if touchConnections[lavaBrick] then return end

	touchConnections[lavaBrick] = lavaBrick.Touched:Connect(function(touchingPart)
		local humanoid = humanoidFromPart(touchingPart)
		if humanoid then damageHumanoid(humanoid, lavaBrick) end
	end)
end

for _, descendant in ipairs(lavaFolder:GetDescendants()) do register(descendant) end
register(lavaFolder)

for lavaBrick in pairs(lavaParts) do connectTouchDamage(lavaBrick) end

lavaFolder.DescendantAdded:Connect(function(instance)
	register(instance)
	if instance:IsA("BasePart") and lavaParts[instance] then connectTouchDamage(instance) end
end)
lavaFolder.DescendantRemoving:Connect(function(instance)
	lavaParts[instance :: any] = nil
	if instance:IsA("BasePart") then
		local connection = touchConnections[instance]
		if connection then connection:Disconnect() end
		touchConnections[instance] = nil
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < OVERLAP_INTERVAL then return end
	accumulator %= OVERLAP_INTERVAL

	local damagedThisScan: {[Humanoid]: boolean} = {}
	for lavaBrick in pairs(lavaParts) do
		if not lavaBrick.Parent then
			lavaParts[lavaBrick] = nil
			continue
		end

		for _, touchingPart in ipairs(Workspace:GetPartsInPart(lavaBrick, overlapParams)) do
			local humanoid = humanoidFromPart(touchingPart)
			if not humanoid or humanoid.Health <= 0 or damagedThisScan[humanoid] then continue end
			damagedThisScan[humanoid] = true
			damageHumanoid(humanoid, lavaBrick)
		end
	end
end)

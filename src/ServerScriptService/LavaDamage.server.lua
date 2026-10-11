-- Server-authoritative damage for every LavaBrick and LavaBrick1Tap inside
-- Workspace.LavaBricks. Touch events catch short landings while jumping;
-- the overlap scan is retained for characters that begin inside a lava part.
-- A humanoid can take at most one lava tick per second, even when several
-- body parts or lava bricks overlap it at once.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DAMAGE = 30
local ONE_TAP_DAMAGE = 1000
local DAMAGE_COOLDOWN = 2
local OVERLAP_INTERVAL = 0.1

local lavaFolder = Workspace:WaitForChild("LavaBricks")
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = {Workspace}

local lavaParts: {[BasePart]: boolean} = {}
local nextDamageAt = setmetatable({}, {__mode = "k"})
local touchConnections: {[BasePart]: RBXScriptConnection} = {}

local function isLavaBrick(instance: Instance): boolean
	return instance:IsA("BasePart")
		and (instance.Name == "LavaBrick" or instance.Name == "LavaBrick1Tap")
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
	local oneTap = lavaBrick.Name == "LavaBrick1Tap"
	-- A one-tap brick must still kill if the player just touched ordinary lava.
	if not oneTap and now < (nextDamageAt[humanoid] or 0) then return end

	nextDamageAt[humanoid] = now + DAMAGE_COOLDOWN
	local amount = oneTap and ONE_TAP_DAMAGE or DAMAGE
	-- Mark the killing blow before health changes so the death handler sees it.
	-- A hit that does not actually kill must not stick to a later death.
	local marked = false
	if humanoid.Health - amount <= 0 and not humanoid:GetAttribute("DeathCause") then
		humanoid:SetAttribute("DeathCause", "Lava")
		marked = true
	end
	humanoid:TakeDamage(amount)
	if marked and humanoid.Health > 0 then humanoid:SetAttribute("DeathCause", nil) end

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

		-- Resting limbs can touch the surface without penetrating its volume.
		local contacts = Workspace:GetPartsInPart(lavaBrick, overlapParams)
		for _, part in ipairs(lavaBrick:GetTouchingParts()) do table.insert(contacts, part) end
		for _, touchingPart in ipairs(contacts) do
			local humanoid = humanoidFromPart(touchingPart)
			if not humanoid or humanoid.Health <= 0
				or (damagedThisScan[humanoid] and lavaBrick.Name ~= "LavaBrick1Tap") then continue end
			damagedThisScan[humanoid] = true
			damageHumanoid(humanoid, lavaBrick)
		end
	end
end)

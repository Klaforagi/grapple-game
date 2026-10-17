-- Every client renders sparkles on Gold guns, bombs, and active ropes.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

local templates = ReplicatedStorage:WaitForChild("Templates", 10)
local sparkle = templates and templates:WaitForChild("Sparkle", 10)
if not sparkle then return end

local sources = {}
if sparkle:IsA("ParticleEmitter") then table.insert(sources, sparkle) end
for _, descendant in ipairs(sparkle:GetDescendants()) do
	if descendant:IsA("ParticleEmitter") then table.insert(sources, descendant) end
end
if #sources == 0 then return end

local NODE_COUNT = 10
local MAX_GUN_PARTS = 6
local TRAVEL_SPEED = 0.22
local UPDATE_INTERVAL = 1 / 30
local random = Random.new()
local beams = {}
local guns = {}
local bombs = {}
local maxLifetime = 0
for _, source in ipairs(sources) do
	maxLifetime = math.max(maxLifetime, source.Lifetime.Max)
end

local function retire(state)
	if not state.nodes then return end
	for _, node in ipairs(state.nodes) do
		for _, emitter in ipairs(node:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
		end
		Debris:AddItem(node, maxLifetime + 0.1)
	end
	state.nodes = nil
	state.emitters = nil
end

local function scheduleEmitter(source, attachment, count, now, emitters, part)
	local emitter = source:Clone()
	-- Automatic emission starts every clone on the same frame. Schedule each
	-- point separately so sparkles appear at different times.
	emitter.Rate = 0
	emitter.Enabled = true
	emitter.Parent = attachment
	local interval = source.Rate > 0 and count / source.Rate or 1
	table.insert(emitters, {
		emitter = emitter,
		attachment = attachment,
		part = part,
		interval = interval,
		nextAt = now + random:NextNumber(0, interval),
	})
end

local function randomSurfacePoint(part)
	local size = part.Size
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		local z = random:NextNumber(-1, 1)
		local angle = random:NextNumber(0, 2 * math.pi)
		local ring = math.sqrt(1 - z * z)
		return Vector3.new(
			ring * math.cos(angle) * size.X * 0.5,
			z * size.Y * 0.5,
			ring * math.sin(angle) * size.Z * 0.5
		)
	end
	local x = random:NextNumber(-0.5, 0.5) * size.X
	local y = random:NextNumber(-0.5, 0.5) * size.Y
	local z = random:NextNumber(-0.5, 0.5) * size.Z
	local face = random:NextInteger(1, 6)
	if face <= 2 then x = (face == 1 and 0.5 or -0.5) * size.X
	elseif face <= 4 then y = (face == 3 and 0.5 or -0.5) * size.Y
	else z = (face == 5 and 0.5 or -0.5) * size.Z end
	return Vector3.new(x, y, z)
end

local function startSurface(state, parts, now, maxParts, attachmentName)
	table.sort(parts, function(a, b)
		return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
	end)
	local count = math.min(#parts, maxParts)
	if count == 0 then return end
	local attachments = {}
	local emitters = {}
	for index = 1, count do
		local part = parts[index]
		local attachment = Instance.new("Attachment")
		attachment.Name = attachmentName
		attachment.Position = randomSurfacePoint(part)
		attachment.Parent = part
		table.insert(attachments, attachment)
		for _, source in ipairs(sources) do
			scheduleEmitter(source, attachment, count, now, emitters, part)
		end
	end
	state.attachments = attachments
	state.emitters = emitters
end

local function startGun(state, tool, now)
	local parts = {}
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.95
			and descendant:GetAttribute("RainbowPalette") == "Gold" then
			table.insert(parts, descendant)
		end
	end
	startSurface(state, parts, now, MAX_GUN_PARTS, "GoldGunSparkle")
end

local function retireSurface(state)
	if not state.attachments then return end
	for _, attachment in ipairs(state.attachments) do
		for _, emitter in ipairs(attachment:GetChildren()) do
			if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
		end
		Debris:AddItem(attachment, maxLifetime + 0.1)
	end
	state.attachments = nil
	state.emitters = nil
end

local function emitDue(emitters, now)
	for _, entry in ipairs(emitters) do
		if now >= entry.nextAt then
			if entry.part then entry.attachment.Position = randomSurfacePoint(entry.part) end
			entry.emitter:Emit(1)
			entry.nextAt = now + entry.interval * random:NextNumber(0.65, 1.35)
		end
	end
end

local function start(state, origin, target, now)
	local nodes = {}
	local emitters = {}
	for index = 1, NODE_COUNT do
		local node = Instance.new("Part")
		node.Name = "GoldRopeSparkle"
		node.Size = Vector3.new(0.1, 0.1, 0.1)
		node.Transparency = 1
		node.Anchored = true
		node.CanCollide = false
		node.CanTouch = false
		node.CanQuery = false
		node.CastShadow = false
		node.CFrame = CFrame.new(origin:Lerp(target, (index - 1) / NODE_COUNT))
		local attachment = Instance.new("Attachment")
		attachment.Parent = node
		for _, source in ipairs(sources) do
			scheduleEmitter(source, attachment, NODE_COUNT, now, emitters)
		end
		node.Parent = workspace
		nodes[index] = node
	end
	state.nodes = nodes
	state.emitters = emitters
end

local function watch(instance)
	if instance:IsA("Beam") and (instance.Name == "Rope" or instance.Name == "RopeVisual") then
		beams[instance] = beams[instance] or {}
	elseif instance:IsA("Tool") and instance.Name == Config.toolName then
		guns[instance] = guns[instance] or {}
	elseif (instance:IsA("Tool") and instance.Name == Config.bombToolName)
		or (instance:IsA("BasePart") and instance.Name == "ThrownBomb") then
		bombs[instance] = bombs[instance] or {}
	end
end

workspace.DescendantAdded:Connect(watch)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then return end
	elapsed %= UPDATE_INTERVAL
	local now = workspace:GetServerTimeNow()
	for beam, state in pairs(beams) do
		if not beam:IsDescendantOf(workspace) then
			retire(state)
			beams[beam] = nil
		else
			local a, b = beam.Attachment0, beam.Attachment1
			local active = beam.Enabled and beam:GetAttribute("RainbowPalette") == "Gold"
				and a and b and a:IsDescendantOf(workspace) and b:IsDescendantOf(workspace)
			if not active then
				retire(state)
			else
				local origin, target = a.WorldPosition, b.WorldPosition
				if not state.nodes then start(state, origin, target, now) end
				local phase = now * TRAVEL_SPEED
				for index, node in ipairs(state.nodes) do
					local fraction = (phase + (index - 1) / NODE_COUNT) % 1
					node.CFrame = CFrame.new(origin:Lerp(target, fraction))
				end
				emitDue(state.emitters, now)
			end
		end
	end
	for tool, state in pairs(guns) do
		if not tool:IsDescendantOf(workspace) then
			retireSurface(state)
			guns[tool] = nil
		else
			local handle = tool:FindFirstChild("Handle", true)
			if not (handle and handle:IsA("BasePart") and handle:GetAttribute("RainbowPalette") == "Gold") then
				retireSurface(state)
			else
				if not state.attachments then startGun(state, tool, now) end
				if state.emitters then emitDue(state.emitters, now) end
			end
		end
	end
	for object, state in pairs(bombs) do
		if not object:IsDescendantOf(workspace) then
			retireSurface(state)
			bombs[object] = nil
		else
			local part = object:IsA("Tool") and object:FindFirstChild("Handle") or object
			if not (part and part:IsA("BasePart") and part:GetAttribute("RainbowPalette") == "Gold"
				and part.Transparency < 0.95) then
				retireSurface(state)
			else
				if not state.attachments then
					startSurface(state, {part}, now, 1, "GoldBombSparkle")
				end
				if state.emitters then emitDue(state.emitters, now) end
			end
		end
	end
end)

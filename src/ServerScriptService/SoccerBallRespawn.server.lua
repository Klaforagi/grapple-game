local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local RESPAWN_DELAY = 2
local CHECK_INTERVAL = 0.5
local templates = Instance.new("Folder")
templates.Name = "SoccerBallRespawnTemplates"
templates.Parent = ServerStorage

local slots = {}
local tracked = setmetatable({}, {__mode = "k"})

local function bodyParts(model)
	local parts = {}
    if model:IsA("BasePart") then table.insert(parts, model) end
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then table.insert(parts, item) end
	end
	return parts
end

local function register(model)
	if (not model:IsA("Model") and not model:IsA("BasePart")) or model.Name ~= "SoccerBall" or tracked[model]
		or not model:IsDescendantOf(Workspace) then return end
	local parts = bodyParts(model)
	if #parts == 0 then return end
	-- Include non-archivable pieces without changing the live ball's settings.
	local previous = {[model] = model.Archivable}
	model.Archivable = true
	for _, item in ipairs(model:GetDescendants()) do
		previous[item] = item.Archivable
		item.Archivable = true
	end
	local ok, template = pcall(function() return model:Clone() end)
	for item, value in pairs(previous) do item.Archivable = value end
	if not ok or not template then
		warn("[SoccerBallRespawn] Could not save " .. model:GetFullName())
		return
	end
	template.Parent = templates
	tracked[model] = true
	table.insert(slots, {ball = model, parts = parts, template = template,
		spawn = model:GetPivot(), parent = model.Parent})
end

Workspace.DescendantAdded:Connect(function(item)
	task.defer(function()
		local ancestor = item
		while ancestor and ancestor ~= Workspace do
			if (ancestor:IsA("Model") or ancestor:IsA("BasePart")) and ancestor.Name == "SoccerBall" then
				register(ancestor)
				break
			end
			ancestor = ancestor.Parent
		end
	end)
end)
for _, item in ipairs(Workspace:GetDescendants()) do register(item) end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < CHECK_INTERVAL then return end
	elapsed = 0
	local now = os.clock()
	for _, slot in ipairs(slots) do
		if slot.respawnAt then
			if now < slot.respawnAt then continue end
			local replacement = slot.template:Clone()
			tracked[replacement] = true -- A respawn replaces this slot; never creates another.
			replacement:PivotTo(slot.spawn)
			local parts = bodyParts(replacement)
			for _, part in ipairs(parts) do
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
			slot.ball, slot.parts, slot.respawnAt = replacement, parts, nil
			local parent = slot.parent
			replacement.Parent = (parent == Workspace or parent:IsDescendantOf(Workspace)) and parent or Workspace
		else
			local missing = not slot.ball:IsDescendantOf(Workspace)
			for _, part in ipairs(slot.parts) do
				-- Roblox may remove the physical parts but leave an empty Model.
				if (part ~= slot.ball and not part:IsDescendantOf(slot.ball))
					or part.Position.Y < Workspace.FallenPartsDestroyHeight + 10 then
					missing = true
					break
				end
			end
			if missing then
				slot.ball:Destroy()
				slot.respawnAt = now + RESPAWN_DELAY
			end
		end
	end
end)

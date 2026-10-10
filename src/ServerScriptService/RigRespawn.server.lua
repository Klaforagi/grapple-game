-- Keep an untouched template of each non-player humanoid rig before gameplay
-- changes its joints, colors, tools, or position.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local templates = Instance.new("Folder")
templates.Name = "RigRespawnTemplates"
templates.Parent = ServerStorage

local request = ServerStorage:FindFirstChild("RigRespawnRequest")
if not request then
	request = Instance.new("BindableEvent")
	request.Name = "RigRespawnRequest"
	request.Parent = ServerStorage
end

local registered = {}
local register

register = function(humanoid, template, spawnPivot, spawnParent)
	if registered[humanoid] or not humanoid:IsA("Humanoid") then return end
	local rig = humanoid.Parent
	if not rig or not rig:IsA("Model") or not rig:IsDescendantOf(Workspace)
		or Players:GetPlayerFromCharacter(rig) or rig:GetAttribute("AutoRespawn") == false
		or humanoid.Health <= 0 then return end

	if not template then
		local archivable = rig.Archivable
		rig.Archivable = true
		-- Clone silently drops any descendant that is not archivable, including the
		-- Humanoid. The respawn would then have nobody to register.
		for _, descendant in ipairs(rig:GetDescendants()) do
			if descendant.Archivable == false then descendant.Archivable = true end
		end
		local cloned
		local ok, result = pcall(function() return rig:Clone() end)
		rig.Archivable = archivable
		cloned = ok and result or nil
		if not cloned then
			warn("[RigRespawn] Could not clone " .. rig.Name)
			return
		end
		template = cloned
		template.Parent = templates
		spawnPivot, spawnParent = rig:GetPivot(), rig.Parent
	end

	local state = {replacing = false, scheduled = false}
	registered[humanoid] = state
	local died, destroying
	destroying = rig.Destroying:Connect(function()
		registered[humanoid] = nil
		if died then died:Disconnect() end
		if destroying then destroying:Disconnect() end
		if not state.replacing then template:Destroy() end
	end)
	local function scheduleRespawn()
		if state.scheduled then return end
		state.scheduled = true
		local delay = rig:GetAttribute("RespawnDelay")
		if typeof(delay) ~= "number" or delay ~= delay then delay = 5 end
		task.delay(math.clamp(delay, 0, 60), function()
			if registered[humanoid] ~= state then return end
			if rig:GetAttribute("AutoRespawn") == false or not rig:IsDescendantOf(Workspace)
				or not (spawnParent == Workspace or spawnParent:IsDescendantOf(Workspace)) then
				rig:Destroy()
				return
			end

			local ok, replacement = pcall(function() return template:Clone() end)
			if not ok or not replacement then
				state.scheduled = false
				warn("[RigRespawn] Could not clone " .. rig.Name)
				return
			end
			local nextHumanoid = replacement:FindFirstChildOfClass("Humanoid")
			if not nextHumanoid then
				state.scheduled = false
				replacement:Destroy()
				return
			end
			pcall(function() nextHumanoid.Health = nextHumanoid.MaxHealth end)
			pcall(function() replacement:PivotTo(spawnPivot) end)
			state.replacing = true
			rig:Destroy() -- Also lets capsule/grapple cleanup release references.
			replacement.Parent = spawnParent
			register(nextHumanoid, template, spawnPivot, spawnParent)
		end)
	end
	state.schedule = scheduleRespawn
	died = humanoid.Died:Connect(scheduleRespawn)
	-- Capsule capture turns the state machine off. Health can hit zero without Died.
	local function onHealth()
		if humanoid.Health <= 0 then scheduleRespawn() end
	end
	if humanoid.HealthChanged then humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then scheduleRespawn() end
	end) end
	if humanoid.GetPropertyChangedSignal then
		humanoid:GetPropertyChangedSignal("Health"):Connect(onHealth)
	end
end

request.Event:Connect(function(humanoid)
	local state = humanoid and registered[humanoid]
	if state and state.schedule then state.schedule() end
end)

local function discover(instance)
	if instance:IsA("Humanoid") then
		-- Wait until a newly inserted player character has been assigned to its
		-- Player, and until a newly cloned rig has been registered by this script.
		task.defer(function() register(instance) end)
	end
end
Workspace.DescendantAdded:Connect(discover)
for _, instance in ipairs(Workspace:GetDescendants()) do discover(instance) end

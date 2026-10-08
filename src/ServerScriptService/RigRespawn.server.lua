-- Keep an untouched template of each non-player humanoid rig before gameplay
-- changes its joints, colors, tools, or position.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local templates = Instance.new("Folder")
templates.Name = "RigRespawnTemplates"
templates.Parent = ServerStorage

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
		template = rig:Clone()
		rig.Archivable = archivable
		if not template then return end
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
	died = humanoid.Died:Connect(function()
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

			local replacement = template:Clone()
			local nextHumanoid = replacement:FindFirstChildOfClass("Humanoid")
			if not nextHumanoid then
				replacement:Destroy()
				rig:Destroy()
				return
			end
			nextHumanoid.Health = nextHumanoid.MaxHealth
			replacement:PivotTo(spawnPivot)
			state.replacing = true
			rig:Destroy() -- Also lets capsule/grapple cleanup release references.
			replacement.Parent = spawnParent
			register(nextHumanoid, template, spawnPivot, spawnParent)
		end)
	end)
end

local function discover(instance)
	if instance:IsA("Humanoid") then
		-- Wait until a newly inserted player character has been assigned to its
		-- Player, and until a newly cloned rig has been registered by this script.
		task.defer(function() register(instance) end)
	end
end
Workspace.DescendantAdded:Connect(discover)
for _, instance in ipairs(Workspace:GetDescendants()) do discover(instance) end

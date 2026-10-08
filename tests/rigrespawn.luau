return function(source)
	local function signal()
		local callbacks = {}
		return {
			Connect = function(_, callback)
				local connection = {active = true}
				function connection:Disconnect() self.active = false end
				table.insert(callbacks, {connection, callback})
				return connection
			end,
			Emit = function(_, ...)
				for _, entry in ipairs(callbacks) do if entry[1].active then entry[2](...) end end
			end,
		}
	end
	local objects, timers, deferred = {}, {}, {}
	local methods = {}
	local function new(class)
		local item = setmetatable({ClassName = class, attributes = {}, Destroying = signal(),
			Died = signal(), DescendantAdded = signal(), Health = 100, MaxHealth = 100, Archivable = true}, {__index = methods})
		table.insert(objects, item)
		return item
	end
	function methods:IsA(class) return self.ClassName == class end
	function methods:GetAttribute(key) return self.attributes[key] end
	function methods:IsDescendantOf(ancestor)
		local parent = self.Parent
		while parent do if parent == ancestor then return true end parent = parent.Parent end
		return false
	end
	function methods:GetDescendants()
		local result = {}
		for _, item in ipairs(objects) do if item:IsDescendantOf(self) then table.insert(result, item) end end
		return result
	end
	function methods:FindFirstChildOfClass(class)
		for _, item in ipairs(objects) do if item.Parent == self and item:IsA(class) then return item end end
	end
	function methods:GetPivot() return self.pivot end
	function methods:PivotTo(pivot) self.pivot = pivot end
	function methods:Clone()
		local clone = new(self.ClassName)
		clone.Name, clone.pivot, clone.skin = self.Name, self.pivot, self.skin
		clone.attributes = table.clone(self.attributes)
		for _, item in ipairs(self:GetDescendants()) do
			if item.Parent == self then item:Clone().Parent = clone end
		end
		return clone
	end
	function methods:Destroy() self.Destroying:Emit() self.Parent = nil self.destroyed = true end
	local world, storage = new("Workspace"), new("ServerStorage")
	local playerRig = new("Model")
	playerRig.Parent = world
	new("Humanoid").Parent = playerRig
	local r6, r15 = new("Model"), new("Model")
	for index, rig in ipairs({r6, r15}) do
		rig.Parent, rig.pivot, rig.skin = world, index, "original"
		new("Humanoid").Parent = rig
	end
	local services = {Workspace = world, ServerStorage = storage,
		Players = {GetPlayerFromCharacter = function(_, rig) return rig == playerRig and {} or nil end}}
	local fn = assert(loadstring(source))
	setfenv(fn, setmetatable({game = {GetService = function(_, name) return services[name] end},
		Instance = {new = new}, task = {
			defer = function(callback) table.insert(deferred, callback) end,
			delay = function(delay, callback) assert(delay == 5) table.insert(timers, callback) end,
		}, typeof = type}, {__index = getfenv()}))
	fn()
	for _, callback in ipairs(deferred) do callback() end
	playerRig:FindFirstChildOfClass("Humanoid").Died:Emit()
	assert(#timers == 0, "NPC respawner claimed a player character")
	for _, rig in ipairs({r6, r15}) do
		rig.skin, rig.pivot = "frozen", 99
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		humanoid.Health = 0
		humanoid.Died:Emit()
		humanoid.Died:Emit()
	end
	assert(#timers == 2, "duplicate death scheduled extra NPCs")
	for _, callback in ipairs(timers) do callback() end
	table.clear(timers)
	assert(r6.destroyed and r15.destroyed, "dead rigs were not removed")
	local count = 0
	for _, item in ipairs(world:GetDescendants()) do
		if item:IsA("Model") and item ~= playerRig then
			count += 1
			assert(item.skin == "original" and item.pivot ~= 99, "respawn retained frozen appearance or capsule location")
			item:FindFirstChildOfClass("Humanoid").Died:Emit()
		end
	end
	assert(count == 2 and #timers == 2, "replacement rigs cannot respawn again")
end

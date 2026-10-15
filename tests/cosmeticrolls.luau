return function(source, catalog)
	local now, calls, remote, invokeDuringRoll = 10, 0, nil, false
	local function signal()
		local callbacks = {}
		return {Connect = function(_, fn) table.insert(callbacks, fn) end,
			Emit = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end}
	end
	local players = {PlayerAdded = signal(), PlayerRemoving = signal()}
	local health, distance = 100, 0
	local player = {Parent = players, attributes = {}, Character = {
		FindFirstChild = function() return {Position = {}} end,
		FindFirstChildOfClass = function() return {Health = health} end,
	}}
	function player:GetAttribute(key) return self.attributes[key] end
	function player:SetAttribute(key, value) self.attributes[key] = value end
	function players:GetPlayers() return {player} end
	local permitted = true
	local roll = {Invoke = function()
		calls += 1
		if invokeDuringRoll then
			assert(not remote.OnServerInvoke(player, {kind = "Instance", valid = true}, "concurrent").ok, "concurrent request passed")
		end
		return {ok = true, itemId = "Gun_White"}
	end}
	local storage = {Modules = {WaitForChild = function(_, name) return name end}, WaitForChild = function() return roll end}
	local testCatalog = setmetatable({
		IsStationPart = function(zone) return zone.valid end,
		Inside = function() return distance <= 0 end,
	}, {__index = catalog})
	local services = {Players = players, ReplicatedStorage = storage,
		PolicyService = {GetPolicyInfoForPlayerAsync = function() return {ArePaidRandomItemsRestricted = not permitted} end}}
	local env = setmetatable({
		game = {GetService = function(_, name) return services[name] end},
		require = function() return testCatalog end,
		Instance = {new = function() remote = {} return remote end},
		task = {spawn = function(fn, ...) fn(...) end, wait = function() error("unexpected policy retry") end},
		typeof = function(value) return type(value) == "table" and value.kind or type(value) end,
		os = {clock = function() return now end}, warn = function() end,
	}, {__index = getfenv()})
	local fn = assert(loadstring(source)) setfenv(fn, env) fn()
	local zone = {kind = "Instance", valid = true}
	assert(player.attributes.CosmeticRollAllowed)
	assert(not remote.OnServerInvoke(player, zone, {}).ok)
	assert(not remote.OnServerInvoke(player, nil, "request-a").ok)
	assert(not remote.OnServerInvoke(player, {kind = "Instance", valid = false}, "request-a").ok)
	distance = 1
	assert(not remote.OnServerInvoke(player, zone, "request-a").ok)
	distance, health = 0, 0
	assert(not remote.OnServerInvoke(player, zone, "request-a").ok)
	health = 100
	permitted = false players.PlayerAdded:Emit(player)
	assert(not remote.OnServerInvoke(player, zone, "request-a").ok and calls == 0, "restricted player was charged")
	permitted = true players.PlayerAdded:Emit(player)
	invokeDuringRoll = true
	assert(remote.OnServerInvoke(player, zone, "request-a").ok and calls == 1)
	assert(remote.OnServerInvoke(player, zone, "request-a").ok and calls == 1, "lost client response caused another roll")
	assert(not remote.OnServerInvoke(player, zone, "request-b").ok and calls == 1, "cooldown bypassed")
	now += catalog.Cooldown
	assert(remote.OnServerInvoke(player, zone, "request-b").ok and calls == 2)
	print("Cosmetic station: policy, malformed requests, distance, death, concurrency and cooldown passed")
end

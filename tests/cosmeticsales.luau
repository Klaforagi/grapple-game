return function(source, catalog)
	local now, calls, remote, fail, concurrent = 10, 0, nil, false, false
	local players = {PlayerRemoving = {Connect = function() end}}
	local player = {Parent = players}
	local sell = {Invoke = function(_, _, itemId)
		calls += 1
		if concurrent then
			assert(not remote.OnServerInvoke(player, itemId, "other-request").ok, "concurrent sale passed")
		end
		if fail then return {ok = false, retry = true} end
		return {ok = true, copies = 0, price = 500}
	end}
	local storage = {Modules = {WaitForChild = function(_, name) return name end}, WaitForChild = function() return sell end}
	local env = setmetatable({
		game = {GetService = function(_, name) return name == "Players" and players or storage end},
		require = function() return catalog end,
		Instance = {new = function() remote = {} return remote end},
		os = {clock = function() return now end},
	}, {__index = getfenv()})
	local fn = assert(loadstring(source)) setfenv(fn, env) fn()
	assert(not remote.OnServerInvoke(player, {}, "id").ok)
	assert(not remote.OnServerInvoke(player, "Gun_Rainbow", {}).ok)
	assert(not remote.OnServerInvoke(player, "Gun_Gray", "id").ok)
	assert(not remote.OnServerInvoke(player, "Bomb_Banana", "id").ok)
	assert(not remote.OnServerInvoke(player, "Unknown", "id").ok and calls == 0)
	concurrent = true
	assert(remote.OnServerInvoke(player, "Gun_Rainbow", "one").ok and calls == 1)
	assert(remote.OnServerInvoke(player, "Gun_Rainbow", "one").ok and calls == 1, "retry did not reuse receipt")
	assert(not remote.OnServerInvoke(player, "Gun_Rainbow", "two").ok and calls == 1)
	now += 1 fail = true
	assert(remote.OnServerInvoke(player, "Gun_Rainbow", "two").retry and calls == 2)
	now += 1
	assert(not remote.OnServerInvoke(player, "Rope_Rainbow", "three").ok and calls == 2, "unresolved sale was replaced")
	fail = false
	assert(remote.OnServerInvoke(player, "Gun_Rainbow", "two").ok and calls == 3)
	print("Cosmetic sales: invalid requests, protected items, concurrency, cooldown and interrupted retries passed")
end

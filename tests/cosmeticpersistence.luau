return function(source, catalog)
	local function boot(data, owned, admin, failLoad)
		local function signal()
			local callbacks = {}
			return {Connect = function(_, fn) table.insert(callbacks, fn) end,
				Emit = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end}
		end
		local players = {PlayerAdded = signal(), PlayerRemoving = signal()}
		local player = {Name = "Collector", UserId = 1, Parent = players, attributes = {CollectionLoaded = true}}
		for id in pairs(owned or {}) do player.attributes["Owned_" .. id] = true end
		function player:GetAttribute(key) return self.attributes[key] end
		function player:SetAttribute(key, value) self.attributes[key] = value end
		function players:GetPlayers() return {player} end
		local writes = 0
		local store = {GetAsync = function()
			if failLoad then error("unavailable") end
			return data and table.clone(data)
		end, UpdateAsync = function(_, _, transform) writes += 1 data = transform(data) return data end}
		local services = {Players = players, DataStoreService = {GetDataStore = function() return store end},
			Lighting = {ClockTime = 14, GlobalShadows = true}, ReplicatedStorage = {Modules = {WaitForChild = function(_, name) return name end}}}
		local remotes = {SetPlayerSetting = {OnServerEvent = signal()}}
		local env = setmetatable({
			game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
			script = {Parent = {WaitForChild = function(_, name) return name end}},
			require = function(name)
				if name == "CosmeticCatalog" then return catalog end
				if name == "AdminList" then return {IsAdmin = function() return admin == true end} end
				return remotes
			end,
			typeof = type, warn = function() end,
			task = {wait = coroutine.yield, spawn = function(fn, ...)
				local ok, message = coroutine.resume(coroutine.create(fn), ...)
				assert(ok, message)
			end},
		}, {__index = getfenv()})
		local fn = assert(loadstring(source)) setfenv(fn, env) fn()
		return player, function() players.PlayerRemoving:Emit(player) return writes, data end
	end
	local player, leave = boot({GrappleGunColor = "Rainbow", GrappleRopeColor = "Gold", BombColor = "Banana", MusicVolume = 0.4})
	assert(player.attributes.GrappleGunColor == "Gray" and player.attributes.GrappleRopeColor == "Gray" and player.attributes.BombColor == "Cyan")
	assert(player.attributes.MusicVolume == 0.4 and player.attributes.SettingsLoaded)
	local writes, data = leave()
	assert(writes == 1 and data.GrappleGunColor == "Gray")
	player = boot({GrappleGunColor = "Rainbow", BombColor = "Teal"}, {Gun_Rainbow = true, Bomb_Mint = true})
	assert(player.attributes.GrappleGunColor == "Rainbow" and player.attributes.BombColor == "Mint", "owned selections/legacy alias did not restore")
	player = boot({GrappleGunColor = "Black"}, {Gun_Black = true})
	assert(player.attributes.GrappleGunColor == "Black", "owned black selection did not restore")
	player = boot({GrappleGunColor = "Black"})
	assert(player.attributes.GrappleGunColor == "Gray", "unowned black selection did not fall back to gray")
	player = boot({GrappleRopeColor = "Neon Lime"}, {Rope_NeonGreen = true})
	assert(player.attributes.GrappleRopeColor == "Neon Green", "saved Neon Lime selection did not become Neon Green")
	player = boot({BombColor = "Banana"}, nil, true)
	assert(player.attributes.BombColor == "Banana", "admin banana did not restore")
	player, leave = boot({GrappleGunColor = "Rainbow"}, nil, false, true)
	assert(not player.attributes.SettingsLoaded)
	writes, data = leave()
	assert(writes == 0 and data.GrappleGunColor == "Rainbow", "failed load overwrote saved data")
	print("Cosmetic persistence: starters, legacy selections, owned equips, admin banana and load-failure protection passed")
end

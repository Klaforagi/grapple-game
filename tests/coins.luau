return function(source, cosmeticCatalog, cosmeticTransaction)
	local now, saved, heartbeat, leaving, shutdown = 0, nil, nil, nil, nil
	local player = {Name = "CoinTester", UserId = 77, attributes = {}}
	function player:SetAttribute(key, value)
		assert(not string.find(key, " ", 1, true), "Roblox rejects spaces in attribute names")
		self.attributes[key] = value
	end
	function player:GetAttribute(key) return self.attributes[key] end
	local players = {PlayerAdded = {Connect = function() end},
		PlayerRemoving = {Connect = function(_, fn) leaving = fn end}}
	function players:GetPlayers() return {player} end
	function players:GetPlayerByUserId(id)
		if id == player.UserId then return player end
	end
	local store = {}
	local failAfterCommit = false
	function store:GetAsync() return saved end
	function store:UpdateAsync(_, transform)
		local updated = transform(saved)
		if updated == nil then return nil end
		saved = updated
		if failAfterCommit then failAfterCommit = false error("response lost after commit") end
		return saved
	end
	local session = 0
	local made = {}
	local function blank()
		local attributes = {}
		return {
			GetChildren = function() return {} end,
			FindFirstChild = function() end,
			GetAttribute = function(_, key) return attributes[key] end,
			SetAttribute = function(_, key, value) attributes[key] = value end,
			Destroy = function() end,
			IsA = function() return false end,
		}
	end
	local services = {
		Players = players, DataStoreService = {GetDataStore = function() return store end},
		ReplicatedStorage = blank(),
		HttpService = {GenerateGUID = function() session += 1 return tostring(session) end},
		RunService = {Heartbeat = {Connect = function(_, fn) heartbeat = fn end}},
	}
	local env = setmetatable({
		require = function(name)
			if name == "CosmeticCatalog" then return cosmeticCatalog end
			if name == "CosmeticTransaction" then return cosmeticTransaction end
			error("unexpected module " .. tostring(name))
		end,
		Random = {new = function() return {NextNumber = function() return 0.9 end, NextInteger = function(_, first) return first end} end},
		game = {GetService = function(_, name) return services[name] end,
			BindToClose = function(_, fn) shutdown = fn end},
		Instance = {new = function()
			local object = blank()
			made[#made + 1] = object
			return object
		end},
		os = {clock = function() return now end, time = function() return 1000 + now end},
		task = {spawn = function(fn, ...) fn(...) end, wait = function() error("unexpected retry") end},
	}, {__index = getfenv()})
	services.ReplicatedStorage.Modules = {WaitForChild = function(_, name) return name end}
	local function boot()
		local fn = assert(loadstring(source))
		setfenv(fn, env)
		fn()
	end
	boot()
	assert(player.attributes.Coins == 0, "new player did not start at zero")
	now = 59.9 heartbeat()
	assert(player.attributes.Coins == 0, "coin awarded before full minute")
	now = 60 heartbeat()
	assert(player.attributes.Coins == 1 and saved.coins == 1 and saved.earned == 1, "minute reward did not save")
	heartbeat()
	assert(saved.coins == 1 and saved.earned == 1, "duplicate frame awarded another coin")
	now = 180 heartbeat()
	assert(saved.coins == 3 and saved.earned == 3, "missed frames lost full-minute rewards")
	leaving(player)
	boot()
	assert(player.attributes.Coins == 3, "rejoin lost saved coins")
	now = 240 heartbeat()
	assert(player.attributes.Coins == 4, "rejoin minute did not award correctly")
	shutdown()
	assert(saved.coins == 4 and saved.earned == 4, "shutdown duplicated coins")
	local grant
	for index = 1, #made do
		if made[index].Name == "GrantCoins" then grant = made[index] end
	end
	assert(type(grant) == "table" and type(grant.OnInvoke) == "function", "coin grant was not created")
	assert(grant.OnInvoke(77, 100, "receipt-1") == true, "grant failed")
	assert(saved.coins == 104 and saved.earned == 104, "grant did not add coins")
	assert(player.attributes.Coins == 104, "grant did not update the balance")
	assert(grant.OnInvoke(77, 100, "receipt-1") == true, "retry failed")
	assert(saved.coins == 104 and saved.earned == 104, "grant paid twice")
	assert(grant.OnInvoke(77, 0, "receipt-3") == false, "zero grant accepted")
	assert(saved.coins == 104, "rejected grant changed coins")
	local spend, refund
	for index = 1, #made do
		if made[index].Name == "SpendCoins" then spend = made[index] end
		if made[index].Name == "RefundHeldCoins" then refund = made[index] end
	end
	assert(type(spend) == "table" and type(spend.OnInvoke) == "function", "coin spend was not created")
	assert(spend.OnInvoke(77, 10) == true, "spend failed")
	assert(saved.coins == 94 and saved.earned == 104, "spend changed lifetime coins")
	assert(player.attributes.Coins == 94, "spend did not update the held balance")
	assert(spend.OnInvoke(77, 1000) == false, "overspend was accepted")
	assert(saved.coins == 94 and saved.earned == 104, "failed spend changed coins")
	assert(spend.OnInvoke(77, 0) == false, "zero spend was accepted")
	assert(refund.OnInvoke(77, 10) == true, "refund failed")
	assert(saved.coins == 104 and saved.earned == 104, "refund changed lifetime coins")
	assert(player.attributes.Coins == 104, "refund did not restore the held balance")
	local admin
	for index = 1, #made do
		if made[index].Name == "AdminCoins" then admin = made[index] end
	end
	assert(type(admin) == "table" and type(admin.OnInvoke) == "function", "admin coin reset was not created")
	local earnedBefore = player.attributes.CoinsEarned
	assert(admin.OnInvoke("grant", 77, 50) == true, "admin coin grant failed")
	assert(saved.coins == 154 and saved.earned == 104, "admin grant changed lifetime coins")
	assert(player.attributes.Coins == 154 and player.attributes.CoinsEarned == earnedBefore, "admin grant changed the live lifetime")
	assert(admin.OnInvoke("reset", 77) == true, "admin coin reset failed")
	assert(saved.coins == 0 and saved.earned == 0, "admin reset left coins behind")
	assert(player.attributes.Coins == 0 and player.attributes.CoinsEarned == nil, "admin reset left the live balance")
	now = 300
	heartbeat()
	assert(player.attributes.Coins == 1 and saved.coins == 1 and saved.earned == 1, "minute after a reset restored the old total")
	assert(admin.OnInvoke("grant", 77, 500))
	local roll
	for _, object in ipairs(made) do if object.Name == "RollCosmetic" then roll = object end end
	local first = roll.OnInvoke(player)
	assert(first.ok and not first.duplicate and saved.coins == 401 and saved.earned == 1)
	assert(player.attributes["Owned_" .. first.itemId] and saved.cosmetics[first.itemId], "unlock was not published/saved")
	local second = roll.OnInvoke(player)
	assert(second.ok and second.duplicate and second.copies == 2 and saved.coins == 301)
	failAfterCommit = true
	local failed = roll.OnInvoke(player)
	assert(not failed.ok and saved.coins == 201, "ambiguous write did not commit")
	local recovered = roll.OnInvoke(player)
	assert(recovered.ok and saved.coins == 201 and player.attributes.Coins == 201, "retry charged twice or left stale balance")
	assert(recovered.copies == 3 and saved.cosmetics[first.itemId] == 3, "retry added an extra copy")
	leaving(player)
	player.attributes = {}
	boot()
	assert(player.attributes["Owned_" .. first.itemId] and player.attributes.CollectionLoaded, "rejoin lost collection")
	assert(player.attributes.Coins == 201, "rejoin lost roll balance")
	assert(player.attributes["Owned_" .. first.itemId] == 3, "rejoin lost stack quantity")
	-- Previously saved true values still publish as one copy.
	saved.cosmetics.Gun_Rainbow = true
	leaving(player)
	player.attributes = {}
	boot()
	assert(player.attributes.Owned_Gun_Rainbow == 1, "legacy ownership did not load as one copy")
	local sale
	for _, object in ipairs(made) do if object.Name == "SellCosmetic" then sale = object end end
	player:SetAttribute("GrappleGunColor", "Rainbow")
	local sold = sale.OnInvoke(player, "Gun_Rainbow", "sale-1")
	assert(sold.ok and sold.price == 500 and saved.coins == 701 and saved.earned == 1)
	assert(player.attributes.Owned_Gun_Rainbow == 0 and player.attributes.GrappleGunColor == "Gray", "last copy did not fall back to starter")
	assert(sale.OnInvoke(player, "Gun_Rainbow", "sale-1").ok and saved.coins == 701, "sale retry duplicated credit")
	assert(not sale.OnInvoke(player, "Gun_Rainbow", "sale-2").ok and saved.coins == 701, "oversold")
	assert(not sale.OnInvoke(player, "Gun_Gray", "sale-3").ok and saved.coins == 701, "sold default")
	local item = cosmeticCatalog.ById[first.itemId]
	player:SetAttribute(cosmeticCatalog.Attributes[item.Kind], item.Name)
	assert(sale.OnInvoke(player, item.Id, "sale-4").ok and saved.coins == 711)
	assert(player.attributes["Owned_" .. item.Id] == 2 and player:GetAttribute(cosmeticCatalog.Attributes[item.Kind]) == item.Name,
		"selling a spare changed equipped skin")
	failAfterCommit = true
	assert(not sale.OnInvoke(player, item.Id, "sale-5").ok and saved.coins == 721)
	assert(sale.OnInvoke(player, item.Id, "sale-5").ok and saved.coins == 721 and saved.cosmetics[item.Id] == 1,
		"ambiguous sale retry paid twice")
	assert(sale.OnInvoke(player, item.Id, "sale-6").ok and saved.coins == 731 and saved.cosmetics[item.Id] == 0)
	saved.cosmetics["Rope_Neon Red"] = 2
	saved.cosmetics.Rope_NeonLime = 1
	leaving(player)
	player.attributes = {}
	boot()
	assert(player.attributes.Coins == 731 and player.attributes["Owned_" .. item.Id] == 0, "rejoin restored sold copies or lost proceeds")
	assert(player.attributes.Owned_Rope_NeonRed == 2 and saved.cosmetics["Rope_Neon Red"] == nil,
		"legacy Neon copies were not published with a safe attribute name")
	assert(player.attributes.Owned_Rope_NeonGreen == 1 and saved.cosmetics.Rope_NeonLime == nil,
		"Neon Lime copies were not migrated to Neon Green")
end

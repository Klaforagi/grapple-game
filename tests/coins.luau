return function(source)
	local now, saved, heartbeat, leaving, shutdown = 0, nil, nil, nil, nil
	local player = {Name = "CoinTester", UserId = 77, attributes = {}}
	function player:SetAttribute(key, value) self.attributes[key] = value end
	local players = {PlayerAdded = {Connect = function() end},
		PlayerRemoving = {Connect = function(_, fn) leaving = fn end}}
	function players:GetPlayers() return {player} end
	function players:GetPlayerByUserId(id)
		if id == player.UserId then return player end
	end
	local store = {}
	function store:GetAsync() return saved end
	function store:UpdateAsync(_, transform)
		saved = transform(saved)
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
end

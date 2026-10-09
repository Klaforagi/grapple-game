return function(source)
	local now, saved, heartbeat, leaving, shutdown = 0, nil, nil, nil, nil
	local player = {Name = "CoinTester", UserId = 77, attributes = {}}
	function player:SetAttribute(key, value) self.attributes[key] = value end
	local players = {PlayerAdded = {Connect = function() end},
		PlayerRemoving = {Connect = function(_, fn) leaving = fn end}}
	function players:GetPlayers() return {player} end
	local store = {}
	function store:GetAsync() return saved end
	function store:UpdateAsync(_, transform)
		saved = transform(saved)
		return saved
	end
	local session = 0
	local services = {
		Players = players, DataStoreService = {GetDataStore = function() return store end},
		HttpService = {GenerateGUID = function() session += 1 return tostring(session) end},
		RunService = {Heartbeat = {Connect = function(_, fn) heartbeat = fn end}},
	}
	local env = setmetatable({
		game = {GetService = function(_, name) return services[name] end,
			BindToClose = function(_, fn) shutdown = fn end},
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
	assert(player.attributes.Coins == 1 and saved.coins == 1, "minute reward did not save")
	heartbeat()
	assert(saved.coins == 1, "duplicate frame awarded another coin")
	now = 180 heartbeat()
	assert(saved.coins == 3, "missed frames lost full-minute rewards")
	leaving(player)
	boot()
	assert(player.attributes.Coins == 3, "rejoin lost saved coins")
	now = 240 heartbeat()
	assert(player.attributes.Coins == 4, "rejoin minute did not award correctly")
	shutdown()
	assert(saved.coins == 4, "shutdown duplicated coins")
end

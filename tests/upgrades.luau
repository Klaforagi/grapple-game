return function(serverSource, catalogSource)
	local Catalog = assert(loadstring(catalogSource))()
	assert(Catalog.MaxRank == 10, "upgrade ranks are not 10")
	assert(#Catalog.Costs == 10, "each rank needs a coin cost")
	local total = 0
	for _, cost in ipairs(Catalog.Costs) do total += cost end
	assert(total == 23460, "coin costs drifted")
	assert(Catalog.RobuxPrice == 299, "robux rank price drifted")
	assert(Catalog.Cost(0) == 25 and Catalog.Cost(1) == 60 and Catalog.Cost(9) == 10000 and Catalog.Cost(10) == nil, "rank cost lookup failed")

	local function fake(map)
		return {GetAttribute = function(_, key) return map[key] end}
	end
	local fresh = fake({})
	assert(Catalog.HookSpeed(fresh) == 40, "base hook speed")
	assert(Catalog.HookDistance(fresh) == 60, "base hook distance")
	assert(Catalog.TetherDuration(fresh) == 20, "base tether duration")
	assert(Catalog.Resistance(fresh) == 0, "base resistance")
	local maxed = fake({
		HookSpeedRank = 10, HookDistanceRank = 10,
		TetherDurationRank = 10, TetherResistanceRank = 10,
	})
	assert(Catalog.HookSpeed(maxed) == 150, "max hook speed")
	assert(Catalog.HookDistance(maxed) == 300, "max hook distance")
	assert(Catalog.WallLengthScale == 3, "wall mode length scale drifted")
	assert(Catalog.ShotDistance(fresh, false) == 60 and Catalog.ShotDistance(fresh, true) == 180, "wall mode base length")
	assert(Catalog.ShotDistance(maxed, true) == 900, "wall mode max length")
	local previousDistance = Catalog.Value(Catalog.ById.distance, 0)
	local previousGain = 0
	for rank = 1, Catalog.MaxRank do
		local distance = Catalog.Value(Catalog.ById.distance, rank)
		local gain = distance - previousDistance
		assert(gain > previousGain, "hook distance gain did not grow at rank " .. rank)
		previousDistance, previousGain = distance, gain
	end
	assert(Catalog.TetherDuration(maxed) == 60, "max tether duration")
	assert(Catalog.Resistance(maxed) == 0.5, "max resistance")
	assert(Catalog.HeldSeconds(maxed, nil) == 60, "npcs should take the full tether")
	assert(Catalog.HeldSeconds(maxed, maxed) == 30, "resistance should cut a max tether in half")
	assert(Catalog.HeldSeconds(fresh, maxed) == 10, "resistance should shorten a base tether")
	assert(Catalog.ApplyResistance(4, 0.75) == 2, "tether floor failed")
	assert(Catalog.Text(Catalog.ById.duration, 1) == "24s", "duration text")
	assert(Catalog.Text(Catalog.ById.resistance, 10) == "50%", "resistance text")
	assert(Catalog.Text(Catalog.ById.speed, 0) == "40 studs/s", "speed text")

	local saved
	local spend = {calls = {}, fail = false}
	function spend:Invoke(userId, amount)
		table.insert(self.calls, {userId, amount})
		if self.fail then return false end
		return true
	end
	local refund = {calls = {}}
	function refund:Invoke(userId, amount)
		table.insert(self.calls, {userId, amount})
		return true
	end
	local attributes = {}
	local players = {PlayerAdded = {Connect = function() end}, PlayerRemoving = {Connect = function() end}}
	local player = {Name = "Upgrader", UserId = 12, Parent = players}
	function player:SetAttribute(key, value) attributes[key] = value end
	function player:GetAttribute(key) return attributes[key] end
	function players:GetPlayers() return {player} end
	local store = {failNext = false}
	function store:GetAsync() return saved end
	function store:UpdateAsync(_, transform)
		if self.failNext then
			self.failNext = false
			error("save failed")
		end
		saved = transform(saved)
		return saved
	end
	local made = {}
	local function remote()
		local obj = {}
		obj.OnServerEvent = {Connect = function(_, fn) obj.handler = fn end}
		function obj:FireClient(...)
			self.sent = self.sent or {}
			table.insert(self.sent, table.pack(...))
		end
		made[#made + 1] = obj
		return obj
	end
	local catalogModule = {Name = "UpgradeCatalog"}
	local modules = {Name = "Modules", WaitForChild = function(_, name)
		assert(name == "UpgradeCatalog", name)
		return catalogModule
	end}
	local children = {SpendCoins = spend, RefundHeldCoins = refund}
	local replicated = {Modules = modules}
	function replicated:FindFirstChild(name) return children[name] end
	function replicated:WaitForChild(name)
		return assert(children[name], name)
	end
	local services = {
		Players = players,
		DataStoreService = {GetDataStore = function() return store end},
		ReplicatedStorage = replicated,
	}
	local env = setmetatable({
		game = {GetService = function(_, name) return assert(services[name], name) end, BindToClose = function() end},
		Instance = {new = remote},
		task = {spawn = function(fn, ...) fn(...) end, wait = function() error("unexpected wait") end},
		warn = function() end,
	}, {__index = getfenv()})
	env.require = function(module)
		assert(module.Name == "UpgradeCatalog", "unexpected require")
		return Catalog
	end
	local function boot()
		local fn = assert(loadstring(serverSource))
		setfenv(fn, env)
		fn()
	end
	local function purchaseRemote()
		for index = #made, 1, -1 do
			if made[index].Name == "PurchaseUpgrade" then return made[index] end
		end
	end
	boot()
	assert(attributes.UpgradesLoaded == true, "upgrades did not load")
	assert(attributes.HookSpeedRank == 0, "new player did not start at rank 0")
	purchaseRemote().handler(player, "nope")
	assert(#spend.calls == 0, "unknown upgrade spent coins")
	purchaseRemote().handler(player, "speed")
	assert(spend.calls[1][1] == 12 and spend.calls[1][2] == 25, "first rank did not cost 25")
	assert(saved.speed == 1 and attributes.HookSpeedRank == 1, "first rank did not save")
	purchaseRemote().handler(player, "speed")
	assert(spend.calls[2][2] == 60 and attributes.HookSpeedRank == 2, "second rank did not cost 60")
	spend.fail = true
	purchaseRemote().handler(player, "speed")
	assert(attributes.HookSpeedRank == 2 and saved.speed == 2, "failed spend raised the rank")
	assert(#refund.calls == 0, "failed spend refunded coins")
	spend.fail = false
	store.failNext = true
	purchaseRemote().handler(player, "speed")
	assert(attributes.HookSpeedRank == 2 and saved.speed == 2, "failed save raised the rank")
	assert(refund.calls[1][1] == 12 and refund.calls[1][2] == 125, "failed save did not refund the cost")
	local loaded = {}
	function player:SetAttribute(key, value) loaded[key] = value end
	boot()
	assert(loaded.HookSpeedRank == 2 and loaded.UpgradesLoaded == true, "rejoin lost upgrade ranks")
	local spent = #spend.calls
	purchaseRemote().handler(player, "distance", "robux")
	assert(#spend.calls == spent and (loaded.HookDistanceRank or 0) == 0, "unpriced robux request changed the rank")
	Catalog.RobuxProductId = 77
	purchaseRemote().handler(player, "distance", "robux")
	assert((loaded.HookDistanceRank or 0) == 0, "robux prompt raised the rank before payment")
	local grant
	for index = #made, 1, -1 do
		if made[index].Name == "GrantUpgradeRobux" then grant = made[index] break end
	end
	assert(type(grant) == "table" and type(grant.OnInvoke) == "function", "robux grant was not created")
	assert(grant.OnInvoke(12, "up-1") == true, "robux receipt did not grant the rank")
	assert(loaded.HookDistanceRank == 1 and saved.distance == 1, "robux rank did not save")
	assert(saved.purchases["up-1"] == "distance" and saved.speed == 2, "robux receipt disturbed other ranks")
	assert(grant.OnInvoke(12, "up-1") == true, "robux receipt retry failed")
	assert(loaded.HookDistanceRank == 1, "robux receipt ranked twice")
	assert(#spend.calls == spent, "robux receipt spent coins")
end

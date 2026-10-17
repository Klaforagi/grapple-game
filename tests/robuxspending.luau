return function(source, shopSource)
	local records = {}
	local writes = 0
	local store = {}
	function store:UpdateAsync(key, transform)
		writes += 1
		records[key] = transform(records[key])
		return records[key]
	end
	local passFinished = {}
	function passFinished:Connect(callback) self.callback = callback end
	local marketplace = {PromptGamePassPurchaseFinished = passFinished}
	function marketplace:GetProductInfoAsync(id, infoType)
		assert(id == 123 and infoType == "GamePass")
		return {PriceInRobux = 299}
	end
	local replicated = {}
	local env = setmetatable({
		game = {GetService = function(_, name)
			if name == "DataStoreService" then
				return {GetDataStore = function(_, storeName)
					assert(storeName == "GrappleRobuxSpent_v1")
					return store
				end}
			end
			if name == "MarketplaceService" then return marketplace end
			if name == "ReplicatedStorage" then return replicated end
			error(name)
		end},
		Instance = {new = function(class)
			assert(class == "BindableFunction")
			return setmetatable({}, {__newindex = function(self, key, value)
				rawset(self, key, value)
				if key == "Parent" then value[self.Name] = self end
			end})
		end},
		Enum = {InfoType = {GamePass = "GamePass"}},
		task = {spawn = function(callback) callback() end, wait = function() end},
		warn = function() error("pass spending was not recorded") end,
	}, {__index = getfenv()})
	local fn = assert(loadstring(source))
	setfenv(fn, env)
	fn()
	local recorder = replicated.RecordRobuxSpent
	assert(recorder and type(recorder.OnInvoke) == "function")
	assert(recorder.OnInvoke(42, "product_a", 49))
	assert(recorder.OnInvoke(42, "product_a", 49))
	assert(records.player_42.spent == 49, "a retried receipt counted twice")
	assert(recorder.OnInvoke(42, "product_b", 19))
	assert(records.player_42.spent == 68, "separate receipts did not add up")
	passFinished.callback({UserId = 42}, 123, true)
	passFinished.callback({UserId = 42}, 123, true)
	assert(records.player_42.spent == 367, "a pass purchase was missed or double counted")
	assert(not recorder.OnInvoke(42, "product_bad", -1))
	assert(records.player_42.spent == 367 and writes == 5, "invalid spending was saved")

	local modules = {}
	function modules:WaitForChild(name) return {Name = name} end
	replicated.Modules = modules
	replicated.GrappleConfig = {Name = "GrappleConfig"}
	function replicated:WaitForChild(name) return assert(self[name], name) end
	for _, name in ipairs({"GrantCoins", "GrantUpgradeRobux", "GrantEscapeRobux", "GrantEscapeKillRobux"}) do
		replicated[name] = {Invoke = function() return true end}
	end
	env.require = function(module)
		if module.Name == "ShopCatalog" then return {Coins = {{id = 1000, amount = 100}}} end
		if module.Name == "UpgradeCatalog" then return {RobuxProductId = 0} end
		if module.Name == "GrappleConfig" then return {escapeRobuxProductId = 0, escapeKillRobuxProductId = 0} end
		error(module.Name)
	end
	env.Enum.ProductPurchaseDecision = {PurchaseGranted = "granted", NotProcessedYet = "retry"}
	local shop = assert(loadstring(shopSource))
	setfenv(shop, env)
	shop()
	local receipt = {PlayerId = 42, PurchaseId = "receipt_1", ProductId = 1000, CurrencySpent = 49}
	assert(marketplace.ProcessReceipt(receipt) == "granted")
	assert(marketplace.ProcessReceipt(receipt) == "granted")
	assert(records.player_42.spent == 416, "product receipt spending was missed or double counted")
	assert(marketplace.ProcessReceipt({PlayerId = 42, PurchaseId = "unknown", ProductId = 2000, CurrencySpent = 99}) == "retry")
	assert(records.player_42.spent == 416, "unknown product counted as spending")
end

return function(sources)
	local env = setmetatable({
		Color3 = {fromRGB = function(...) return {...} end, fromHSV = function(...) return {...} end, new = function(...) return {...} end},
		script = {Parent = {Parent = {WaitForChild = function(_, name) return name end}}},
	}, {__index = getfenv()})
	local function execute(source)
		local fn = assert(loadstring(source))
		setfenv(fn, env)
		return fn()
	end
	local palettes = execute(sources.itemColors)
	env.require = function(name) assert(name == "ItemColors") return palettes end
	local catalog = execute(sources.cosmeticCatalog)
	local transaction = execute(sources.cosmeticTransaction)
	local player = {attributes = {}}
	function player:GetAttribute(key) return self.attributes[key] end
	local count, total = catalog.Count(player)
	assert(count == 3 and total == 42, "starter/collection count changed: " .. total)
	assert(catalog.Owns(player, "Gun", "Black") and catalog.Owns(player, "Rope", "Gray") and catalog.Owns(player, "Bomb", "Cyan"))
	assert(not catalog.Owns(player, "Gun", "Rainbow") and not catalog.Owns(player, "Gun", "Gold"))
	assert(not catalog.Owns(player, "Bomb", "Banana"))
	player.attributes.Admin = true
	assert(catalog.Owns(player, "Bomb", "Banana"))
	assert(catalog.Count(player) == 3, "admin item changed collection denominator")
	for _, pool in pairs(catalog.Pools) do
		for _, item in ipairs(pool) do
			assert(not item.Starter and item.Name ~= "Gold" and item.Name ~= "Banana")
		end
	end
	local function random(values, pickLast)
		local index = 0
		return {NextNumber = function()
			index += 1
			assert(values[index] ~= nil, "too many rarity checks")
			return values[index]
		end, NextInteger = function(_, first, last) return pickLast and last or first end}
	end
	assert(catalog.Roll(random({0.00099})).Rarity == "Legendary")
	assert(catalog.Roll(random({0.001, 0.34999})).Rarity == "Uncommon")
	assert(catalog.Roll(random({0.001, 0.35})).Rarity == "Common")
	assert(catalog.Roll(random({0.9, 0.9}, true)) == catalog.Pools.Common[#catalog.Pools.Common], "last pool entry unreachable")
	local tiers, odds = catalog.Odds()
	assert(math.abs(tiers.Legendary - 0.001) < 1e-10)
	assert(tiers.Epic == 0 and tiers.Rare == 0)
	assert(math.abs(tiers.Uncommon - 0.34965) < 1e-10)
	assert(math.abs(tiers.Common - 0.64935) < 1e-10)
	local sum = 0
	for id, chance in pairs(odds) do
		sum += chance
		assert(not catalog.ById[id].Starter)
	end
	assert(math.abs(sum - 1) < 1e-10, "odds do not sum to 100%")
	assert(math.abs(odds.Gun_Rainbow - 0.001 / 3) < 1e-10)
	-- Future populated tiers use the same independent highest-first checks.
	local epic, rare = {Rarity = "Epic"}, {Rarity = "Rare"}
	table.insert(catalog.Pools.Epic, epic) table.insert(catalog.Pools.Rare, rare)
	assert(catalog.Roll(random({0.5, 0.009})) == epic)
	assert(catalog.Roll(random({0.5, 0.01, 0.099})) == rare)
	assert(catalog.Roll(random({0.5, 0.01, 0.1, 0.349})).Rarity == "Uncommon")
	table.clear(catalog.Pools.Epic) table.clear(catalog.Pools.Rare)
	for _, rarity in ipairs({"Common", "Uncommon", "Legendary"}) do
		local item = catalog.Pools[rarity][1]
		local request = {id = rarity, itemId = item.Id}
		local record = transaction.Apply({coins = 500, earned = 900}, request, catalog)
		assert(record.coins == 400 and record.earned == 900 and record.cosmetics[item.Id])
		assert(not record.lastCosmeticRoll.duplicate and record.lastCosmeticRoll.refund == 0)
		record = transaction.Apply(record, request, catalog)
		assert(record.coins == 400, "retried request charged twice")
		request = {id = rarity .. "2", itemId = item.Id}
		record = transaction.Apply(record, request, catalog)
		assert(record.coins == 300 + catalog.Rarity(rarity).Refund and record.earned == 900)
		assert(record.lastCosmeticRoll.duplicate)
	end
	assert(transaction.Apply({coins = 99, cosmetics = {Gun_Rainbow = true}}, {id = "poor", itemId = "Gun_Rainbow"}, catalog) == nil,
		"duplicate refund allowed a roll without full price")
	assert(transaction.Apply({coins = 100}, {id = "invalid", itemId = "Gun_Black"}, catalog) == nil)
	assert(transaction.Apply({coins = 100}, {id = "invalid", itemId = "Bomb_Banana"}, catalog) == nil)
	print("Cosmetics: catalog, sequential odds, ownership, exclusions, atomic rewards and refunds passed")
	return catalog, transaction
end

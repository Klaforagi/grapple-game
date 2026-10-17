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
	assert(count == 3 and total == 81, "starter/collection count changed: " .. total)
	for kind, expectedTotal in pairs({All = 81, Gun = 42, Rope = 26, Bomb = 13}) do
		local owned, available = catalog.Count(player, kind)
		assert(owned == (kind == "All" and 3 or 1) and available == expectedTotal, "incorrect tab count for " .. kind)
	end
	assert(catalog.Owns(player, "Gun", "Gray") and catalog.Owns(player, "Rope", "Gray") and catalog.Owns(player, "Bomb", "Cyan"))
	for _, kind in ipairs({"Gun", "Rope", "Bomb"}) do
		assert(catalog.ById[kind .. "_Black"].Rarity == "Uncommon")
		assert(catalog.ById[kind .. "_White"].Rarity == "Uncommon")
		assert(catalog.ById[kind .. "_Rainbow"].Rarity == "Legendary")
		assert(catalog.ById[kind .. "_Gold"].Rarity == "Legendary" and catalog.ById[kind .. "_Gold"].Vip)
	end
	assert(catalog.ById.Gun_Cyan.Rarity == "Uncommon" and catalog.ById.Rope_Cyan.Rarity == "Uncommon")
	assert(catalog.ById.Rope_Chain.Rarity == "Rare" and catalog.ById.Rope_Chain.Color == palettes.Rope.Chain)
	assert(#catalog.Pools.Rare == 18, "expected Chain plus 17 Rare guns")
	local rareGunFinishes = {
		Sandstorm = {198, 168, 138, "Cobblestone"}, Jungle = {62, 121, 44, "Cobblestone"},
		Ice = {6, 166, 198, "Ice"}, Autumn = {255, 119, 0, "LeafyGrass"},
		Brick = {180, 4, 7, "Brick"}, Panther = {0, 0, 0, "Asphalt"},
		Rust = {122, 60, 60, "CorrodedMetal"}, Lava = {226, 123, 38, "CrackedLava"},
		Crimson = {255, 0, 4, "CrackedLava"}, ["Baby Pink"] = {255, 201, 232, "Fabric"},
		["Baby Blue"] = {143, 255, 251, "Fabric"}, Nebula = {47, 0, 148, "Grass"},
		Construction = {255, 213, 0, "Pavement"}, ["Pink Venom"] = {255, 0, 208, "CrackedLava"},
		Grass = {31, 208, 0, "Grass"}, Wooden = {141, 71, 66, "Wood"},
		Ocean = {0, 123, 255, "Marble"},
	}
	for name, expected in pairs(rareGunFinishes) do
		local finish = assert(palettes.RareGuns[name])
		local item = assert(catalog.ById[catalog.Id("Gun", name)])
		assert(item.Rarity == "Rare" and item.Color == finish.Color and palettes.Gun[name] == finish.Color)
		assert(finish.Material == expected[4] and not string.find(item.Id, " ", 1, true))
		for index = 1, 3 do assert(finish.Color[index] == expected[index], name .. " RGB changed") end
	end
	assert(palettes.RareGuns.Ice.Transparency == 0.15)
	local neonRopeColors = {
		["Neon Red"] = {255, 53, 53}, ["Neon Orange"] = {255, 86, 52},
		["Neon Yellow"] = {255, 140, 46}, ["Neon Green"] = {50, 249, 50},
		["Neon Blue"] = {49, 49, 255}, ["Neon Purple"] = {95, 52, 239},
		["Neon Pink"] = {255, 44, 209}, ["Neon Cyan"] = {39, 218, 254},
		["Neon Mint"] = {67, 255, 89},
	}
	local neonGunColors = {
		["Neon Red"] = {255, 115, 117}, ["Neon Orange"] = {255, 132, 101},
		["Neon Yellow"] = {255, 209, 102}, ["Neon Green"] = {91, 185, 89},
		["Neon Blue"] = {98, 106, 255}, ["Neon Purple"] = {130, 99, 255},
		["Neon Pink"] = {251, 149, 255}, ["Neon Cyan"] = {98, 195, 255},
		["Neon Mint"] = {125, 255, 162},
	}
	assert(#catalog.Pools.Epic == 18 and catalog.ById.Rope_NeonLime == nil, "expected nine Epic Neon ropes and guns")
	for neonName, baseName in pairs(palettes.NeonRopes) do
		assert(palettes.NeonGuns[neonName] == baseName, "Neon gun is missing")
		for _, kind in ipairs({"Gun", "Rope"}) do
			local expected = assert(neonRopeColors[neonName])
			local item = catalog.ById[catalog.Id(kind, neonName)]
			assert(item and item.Rarity == "Epic" and not item.Starter)
			assert(not string.find(item.Id, " ", 1, true), "Neon item ID cannot be used as a Roblox attribute")
			assert(item.Color == catalog.ById[kind .. "_" .. baseName].Color, "Neon icon base swatch changed")
			for index = 1, 3 do assert(palettes[kind][neonName][index] == expected[index], "Neon equipment color changed") end
		end
		local gunParts = assert(palettes.NeonGunPartColors[neonName])
		for index = 1, 3 do assert(gunParts[index] == neonGunColors[neonName][index], "Neon gun part color changed") end
	end
	local legacyNeon = { ["Rope_Neon Red"] = 2 }
	catalog.NormalizeCosmetics(legacyNeon)
	assert(legacyNeon.Rope_NeonRed == 2 and legacyNeon["Rope_Neon Red"] == nil, "old Neon copies were not migrated")
	local legacyLime = {Rope_NeonLime = 2, ["Rope_Neon Lime"] = 3, Rope_NeonGreen = 1}
	catalog.NormalizeCosmetics(legacyLime)
	assert(legacyLime.Rope_NeonGreen == 3 and legacyLime.Rope_NeonLime == nil and legacyLime["Rope_Neon Lime"] == nil,
		"Neon Lime copies were not renamed to Neon Green")
	assert(catalog.ById.Bomb_Cyan.Rarity == "Common" and catalog.ById.Bomb_Cyan.Starter)
	assert(catalog.ById.Bomb_Mint.Color == palettes.Swatches.Bomb.Mint and catalog.ById.Bomb_Mint.Color ~= palettes.Bomb.Mint,
		"mint bomb icon should use the softer jade swatch")
	assert(catalog.ById.Gun_Gray.Starter and catalog.ById.Gun_Gray.Rarity == "Common")
	assert(not catalog.ById.Gun_Black.Starter and not catalog.Owns(player, "Gun", "Black"))
	assert(not catalog.Owns(player, "Gun", "Rainbow") and not catalog.Owns(player, "Gun", "Gold"))
	assert(not catalog.Owns(player, "Bomb", "Banana"))
	player.attributes["TestPass_VIP"] = true
	assert(catalog.Owns(player, "Gun", "Gold") and catalog.Owns(player, "Rope", "Gold") and catalog.Owns(player, "Bomb", "Gold"))
	assert(catalog.Count(player) == 6, "VIP gold was not counted as owned")
	player.attributes["TestPass_VIP"] = nil
	assert(not catalog.Owns(player, "Gun", "Gold") and not catalog.Owns(player, "Rope", "Gold") and not catalog.Owns(player, "Bomb", "Gold"))
	player.attributes.Admin = true
	assert(catalog.Owns(player, "Bomb", "Banana"))
	assert(catalog.Count(player) == 3, "admin item changed collection denominator")
	local bombOwned, bombTotal = catalog.Count(player, "Bomb")
	assert(bombOwned == 1 and bombTotal == 13, "admin item changed bomb collection count")
	player.attributes.Owned_Gun_Rainbow = true
	assert(catalog.Copies(player, "Gun", "Rainbow") == 1, "legacy boolean did not migrate")
	player.attributes.Owned_Gun_Rainbow = 7
	assert(catalog.Copies(player, "Gun", "Rainbow") == 7 and catalog.Count(player) == 4, "stacks counted as unique items")
	assert(catalog.Count(player, "Gun") == 2 and catalog.Count(player, "Rope") == 1 and catalog.Count(player, "Bomb") == 1,
		"tab counts included other categories or duplicate copies")
	player.attributes.Owned_Gun_Rainbow = nil
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
	assert(catalog.Roll(random({0.00499})).Rarity == "Legendary")
	assert(catalog.Roll(random({0.005, 0.01, 0.1, 0.34999})).Rarity == "Uncommon")
	assert(catalog.Roll(random({0.005, 0.01, 0.1, 0.35})).Rarity == "Common")
	assert(catalog.Roll(random({0.5, 0.5, 0.099})).Rarity == "Rare")
	assert(catalog.Roll(random({0.009, 0.9, 0.9, 0.9})).Rarity == "Common", "base luck treated 0.009 as legendary")
	assert(catalog.Roll(random({0.009}), 2).Rarity == "Legendary", "2x luck did not double the legendary check")
	assert(catalog.Roll(random({0.02, 0.5, 0.5, 0.5}), 2).Rarity == "Common", "2x luck incorrectly boosted the uncommon check")
	assert(catalog.Roll(random({0.9, 0.9, 0.9, 0.9}, true)) == catalog.Pools.Common[#catalog.Pools.Common], "last pool entry unreachable")
	local tiers, odds = catalog.Odds()
	assert(math.abs(tiers.Legendary - 0.005) < 1e-10)
	assert(math.abs(tiers.Epic - 0.00995) < 1e-10 and math.abs(tiers.Rare - 0.098505) < 1e-10)
	assert(math.abs(tiers.Uncommon - 0.31029075) < 1e-10)
	assert(math.abs(tiers.Common - 0.57625425) < 1e-10)
	local sum = 0
	for id, chance in pairs(odds) do
		sum += chance
		assert(not catalog.ById[id].Starter)
	end
	assert(math.abs(sum - 1) < 1e-10, "odds do not sum to 100%")
	local plate = {
		Size = {X = 10, Y = 1, Z = 8},
		IsA = function(_, class) return class == "BasePart" end,
		CFrame = {PointToObjectSpace = function(_, position) return position end},
	}
	assert(catalog.Inside(plate, {X = 0, Y = 0, Z = 0}), "center of the zone did not count")
	assert(catalog.Inside(plate, {X = 4, Y = 3, Z = 2}), "standing on the zone did not count")
	assert(not catalog.Inside(plate, {X = 4, Y = 3, Z = 9}), "beside the zone counted as inside")
	assert(not catalog.Inside(plate, {X = 8, Y = 0, Z = 0}), "near the zone counted as inside")
	assert(catalog.Inside(plate, {X = 6, Y = 0, Z = 0}, catalog.ServerPadding), "server padding rejected the zone edge")
	assert(not catalog.Inside(plate, {X = 0, Y = 8, Z = 0}), "high above the zone counted as standing on it")
	assert(catalog.ById.Bomb_CartoonBomb and catalog.ById.Bomb_CartoonBomb.Rarity == "Legendary",
		"Cartoon Bomb was not added to the legendary roll pool")
	assert(math.abs(odds.Gun_Rainbow - 0.005 / 4) < 1e-10)
	assert(math.abs(odds.Bomb_CartoonBomb - 0.005 / 4) < 1e-10)
	-- Epic and Rare pools use the same independent highest-first checks.
	assert(catalog.Roll(random({0.5, 0.009})) == catalog.Pools.Epic[1])
	assert(catalog.Roll(random({0.5, 0.01, 0.099}, true)) == catalog.Pools.Rare[#catalog.Pools.Rare])
	assert(catalog.Roll(random({0.5, 0.01, 0.1, 0.349})).Rarity == "Uncommon")
	for _, rarity in ipairs({"Common", "Uncommon", "Legendary"}) do
		local item = catalog.Pools[rarity][1]
		local request = {id = rarity, itemId = item.Id}
		local record = transaction.Apply({coins = 500, earned = 900}, request, catalog)
		assert(record.coins == 450 and record.earned == 900 and record.cosmetics[item.Id])
		assert(not record.lastCosmeticRoll.duplicate and record.lastCosmeticRoll.copies == 1)
		record = transaction.Apply(record, request, catalog)
		assert(record.coins == 450 and record.cosmetics[item.Id] == 1, "retried request charged or awarded twice")
		request = {id = rarity .. "2", itemId = item.Id}
		record = transaction.Apply(record, request, catalog)
		assert(record.coins == 400 and record.cosmetics[item.Id] == 2 and record.earned == 900)
		assert(record.lastCosmeticRoll.duplicate)
	end
	local legacy = transaction.Apply({coins = 500, cosmetics = {Gun_Rainbow = true}}, {id = "legacy", itemId = "Gun_Rainbow"}, catalog)
	assert(legacy.cosmetics.Gun_Rainbow == 2 and legacy.coins == 450, "legacy unlock lost when adding a duplicate")
	for _, tier in ipairs({"Epic", "Rare"}) do
		local item = {Id = "Future_" .. tier, Rarity = tier}
		catalog.ById[item.Id] = item
		local result = transaction.Apply({coins = 50, cosmetics = {[item.Id] = 3}}, {id = tier, itemId = item.Id}, catalog)
		assert(result.coins == 0 and result.cosmetics[item.Id] == 4, "future tier refunded instead of stacking")
		catalog.ById[item.Id] = nil
	end
	assert(transaction.Apply({coins = 49, cosmetics = {Gun_Rainbow = true}}, {id = "poor", itemId = "Gun_Rainbow"}, catalog) == nil,
		"duplicate allowed a roll without full price")
	local ticketRecord = transaction.Apply({coins = 0, earned = 0, rollTickets = 2},
		{id = "ticket-1", itemId = "Gun_Rainbow"}, catalog)
	assert(ticketRecord and ticketRecord.coins == 0 and ticketRecord.rollTickets == 1
		and ticketRecord.lastCosmeticRoll.payment == "Ticket", "ticket did not take priority over coins")
	transaction.Apply(ticketRecord, {id = "ticket-1", itemId = "Gun_Rainbow"}, catalog)
	assert(ticketRecord.rollTickets == 1 and ticketRecord.cosmetics.Gun_Rainbow == 1,
		"retried ticket roll charged or awarded twice")
	ticketRecord = transaction.Apply(ticketRecord, {id = "ticket-2", itemId = "Gun_Rainbow"}, catalog)
	assert(ticketRecord.rollTickets == 0 and ticketRecord.cosmetics.Gun_Rainbow == 2,
		"second ticket roll did not stack its item")
	assert(transaction.Apply(ticketRecord, {id = "ticket-3", itemId = "Gun_Rainbow"}, catalog) == nil,
		"roll succeeded with no tickets or coins")
	ticketRecord.coins = catalog.Cost
	ticketRecord = transaction.Apply(ticketRecord, {id = "ticket-4", itemId = "Gun_Rainbow"}, catalog)
	assert(ticketRecord.coins == 0 and ticketRecord.rollTickets == 0
		and ticketRecord.lastCosmeticRoll.payment == "Coins", "coin fallback did not work after tickets ran out")
	assert(transaction.Apply({coins = 100}, {id = "invalid", itemId = "Gun_Gray"}, catalog) == nil)
	assert(transaction.Apply({coins = 100}, {id = "vip", itemId = "Gun_Gold"}, catalog) == nil)
	assert(transaction.Apply({coins = 100}, {id = "invalid", itemId = "Bomb_Banana"}, catalog) == nil)
	assert(transaction.Sell({coins = 0, cosmetics = {Bomb_Gold = 1}}, {id = "vipSale", itemId = "Bomb_Gold"}, catalog) == nil)
	for kind, name in pairs(catalog.Defaults) do
		local id = kind .. "_" .. name
		assert(transaction.Sell({coins = 0, cosmetics = {[id] = 4}}, {id = "starter", itemId = id}, catalog) == nil, "sold a starter")
	end
	assert(transaction.Sell({coins = 0, cosmetics = {Bomb_Banana = 1}}, {id = "admin", itemId = "Bomb_Banana"}, catalog) == nil)
	for tier, expectedPrice in pairs({Common = 10, Uncommon = 25, Rare = 100, Epic = 200, Legendary = 500}) do
		local item = catalog.Pools[tier][1] or {Id = "Future_" .. tier, Rarity = tier}
		local temporary = not catalog.ById[item.Id]
		catalog.ById[item.Id] = item
		local request = {id = "sale_" .. tier, itemId = item.Id}
		local record = transaction.Sell({coins = 20, earned = 700, cosmetics = {[item.Id] = 2}}, request, catalog)
		assert(record.coins == 20 + expectedPrice and record.cosmetics[item.Id] == 1 and record.earned == 700)
		record = transaction.Sell(record, request, catalog)
		assert(record.coins == 20 + expectedPrice and record.cosmetics[item.Id] == 1, "repeated sale paid/removed twice")
		record = transaction.Sell(record, {id = request.id .. "2", itemId = item.Id}, catalog)
		assert(record.cosmetics[item.Id] == 0)
		assert(transaction.Sell(record, {id = request.id .. "3", itemId = item.Id}, catalog) == nil, "sold a missing copy")
		if temporary then catalog.ById[item.Id] = nil end
	end
	local soldLegacy = transaction.Sell({coins = 0, cosmetics = {Gun_Rainbow = true}}, {id = "legacySale", itemId = "Gun_Rainbow"}, catalog)
	assert(soldLegacy.cosmetics.Gun_Rainbow == 0 and soldLegacy.coins == 500)
	print("Cosmetics: catalog, sequential odds, ownership, exclusions, atomic rewards and stack counts passed")
	return catalog, transaction
end

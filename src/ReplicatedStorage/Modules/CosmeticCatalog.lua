-- One catalog drives rolls, inventory, codex, odds, and collection totals.
-- Add new palette entries in ItemColors, then optionally override their rarity here.
local Palettes = require(script.Parent.Parent:WaitForChild("ItemColors"))
local Catalog = {
	Cost = 100,
	SellPrices = {Common = 10, Uncommon = 25, Rare = 100, Epic = 200, Legendary = 500},
	ModelName = "CosmeticRollStation", PartName = "RollZone",
	-- The root sits above the feet, so a floor plate still counts as standing on the zone.
	StandHeight = 5, ServerPadding = 2, BillboardDistance = 60,
	Cooldown = 5,
	Defaults = {Gun = "Gray", Rope = "Gray", Bomb = "Cyan"},
	Attributes = {Gun = "GrappleGunColor", Rope = "GrappleRopeColor", Bomb = "BombColor"},
	Rarities = {
		{Name = "Legendary", Chance = 0.005, Color = Color3.fromRGB(255, 185, 49)},
		{Name = "Epic", Chance = 0.01, Color = Color3.fromRGB(179, 110, 255)},
		{Name = "Rare", Chance = 0.10, Color = Color3.fromRGB(78, 157, 255)},
		{Name = "Uncommon", Chance = 0.35, Color = Color3.fromRGB(71, 203, 142)},
		{Name = "Common", Chance = 1, Color = Color3.fromRGB(152, 169, 190)},
	},
	Items = {}, ById = {}, Pools = {},
}
local overrides = {
	Gun = {Rainbow = "Legendary", Black = "Uncommon", White = "Uncommon", Cyan = "Uncommon",
		Mint = "Uncommon", Lime = "Uncommon", Pink = "Uncommon"},
	Rope = {Rainbow = "Legendary", Black = "Uncommon", White = "Uncommon", Cyan = "Uncommon",
		Mint = "Uncommon", Lime = "Uncommon", Pink = "Uncommon"},
	Bomb = {Rainbow = "Legendary", Black = "Uncommon", White = "Uncommon",
		Mint = "Uncommon", Pink = "Uncommon"},
}
local ranks = {}
for rank, rarity in ipairs(Catalog.Rarities) do
	ranks[rarity.Name] = rank
	Catalog.Pools[rarity.Name] = {}
end
for _, kind in ipairs({"Gun", "Rope", "Bomb"}) do
	local names = {}
	for name in pairs(Palettes[kind]) do
		-- Teal is a legacy Mint alias; Gold is reserved for VIP.
		if name ~= "Gold" and name ~= "Banana" and name ~= "Teal" then
			table.insert(names, name)
		end
	end
	table.insert(names, "Rainbow")
	table.sort(names)
	for _, name in ipairs(names) do
		local item = {
			Id = kind .. "_" .. name, Kind = kind, Name = name,
			Rarity = overrides[kind][name] or "Common",
			Starter = Catalog.Defaults[kind] == name,
			Color = Palettes.Swatches[kind][name] or Color3.new(1, 1, 1),
		}
		table.insert(Catalog.Items, item)
		Catalog.ById[item.Id] = item
		if not item.Starter then table.insert(Catalog.Pools[item.Rarity], item) end
	end
	local gold = {
		Id = kind .. "_Gold", Kind = kind, Name = "Gold", Rarity = "Legendary", Vip = true,
		Color = Palettes.Swatches[kind].Gold,
	}
	table.insert(Catalog.Items, gold)
	Catalog.ById[gold.Id] = gold
end
table.sort(Catalog.Items, function(a, b)
	if a.Rarity ~= b.Rarity then return ranks[a.Rarity] > ranks[b.Rarity] end
	if a.Name ~= b.Name then return a.Name < b.Name end
	return a.Kind < b.Kind
end)

-- Legacy boolean ownership represents one copy. Keep the Owned_ attribute name
-- so existing saves and clients migrate without losing any unlocks.
function Catalog.Quantity(value)
	if value == true then return 1 end
	if type(value) ~= "number" or value ~= value or value == math.huge then return 0 end
	return math.max(0, math.floor(value))
end

function Catalog.NormalizeCosmetics(owned)
	if type(owned) ~= "table" then return owned end
	for _, kind in ipairs({"Gun", "Rope"}) do
		local legacyId, mintId = kind .. "_Teal", kind .. "_Mint"
		local legacyCopies = Catalog.Quantity(owned[legacyId])
		if legacyCopies > 0 then
			owned[mintId] = math.max(Catalog.Quantity(owned[mintId]), legacyCopies)
			owned[legacyId] = nil
		end
	end
	return owned
end

function Catalog.Copies(player, kind, name)
	if kind == "Bomb" and name == "Banana" then return player:GetAttribute("Admin") == true and 1 or 0 end
	-- Gold counts toward the collection, but only VIP ownership unlocks it.
	if name == "Gold" and Catalog.ById[tostring(kind) .. "_Gold"] then
		return player:GetAttribute("TestPass_VIP") == true and 1 or 0
	end
	local item = Catalog.ById[tostring(kind) .. "_" .. tostring(name)]
	if not item then return 0 end
	return item.Starter and 1 or Catalog.Quantity(player:GetAttribute("Owned_" .. item.Id))
end

function Catalog.Owns(player, kind, name)
	return Catalog.Copies(player, kind, name) > 0
end

function Catalog.Count(player, kind)
	local count, total = 0, 0
	for _, item in ipairs(Catalog.Items) do
		if kind and kind ~= "All" and item.Kind ~= kind then continue end
		total += 1
		if Catalog.Owns(player, item.Kind, item.Name) then count += 1 end
	end
	return count, total
end

function Catalog.Rarity(name)
	return Catalog.Rarities[ranks[name]]
end

-- Independent highest-first checks. Empty tiers are skipped, never a dead roll.
-- 2x Luck doubles only Legendary, Epic, and Rare checks; the lower tiers stay unchanged.
local function getsLuckBonus(rarityName)
	return rarityName == "Legendary" or rarityName == "Epic" or rarityName == "Rare"
end

function Catalog.LuckMultiplier(player)
	return player and player:GetAttribute("TestPass_2xLuck") == true and 2 or 1
end

function Catalog.Roll(random, luck)
	local scale = type(luck) == "number" and luck > 1 and luck or 1
	for _, rarity in ipairs(Catalog.Rarities) do
		local pool = Catalog.Pools[rarity.Name]
		local chance = rarity.Chance
		if scale ~= 1 and getsLuckBonus(rarity.Name) then chance = math.min(1, chance * scale) end
		if #pool > 0 and (rarity.Name == "Common" or random:NextNumber() < chance) then
			return pool[random:NextInteger(1, #pool)]
		end
	end
	error("The cosmetic catalog needs at least one rollable Common")
end

function Catalog.Odds(luck)
	local remaining, tiers, items = 1, {}, {}
	local scale = type(luck) == "number" and luck > 1 and luck or 1
	for _, rarity in ipairs(Catalog.Rarities) do
		local pool = Catalog.Pools[rarity.Name]
		local check = rarity.Chance
		if scale ~= 1 and getsLuckBonus(rarity.Name) then check = math.min(1, check * scale) end
		local chance = #pool > 0 and remaining * check or 0
		tiers[rarity.Name] = chance
		remaining -= chance
		for _, item in ipairs(pool) do items[item.Id] = chance / #pool end
	end
	return tiers, items
end

function Catalog.IsStationPart(part)
	if not part:IsA("BasePart") or part.Name ~= Catalog.PartName then return false end
	local model = part:FindFirstAncestor(Catalog.ModelName)
	return model ~= nil and model:IsA("Model") and part:IsDescendantOf(workspace)
end

-- True when the position is inside the oriented zone, or standing on top of it.
-- Padding is only for the server, so a little replication lag still counts as in the zone.
function Catalog.Inside(part, position, padding)
	if (typeof(part) ~= "Instance" and type(part) ~= "table") or not part.IsA or not part:IsA("BasePart") then
		return false
	end
	local point = part.CFrame:PointToObjectSpace(position)
	local pad = padding or 0
	local halfX, halfY, halfZ = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
	return math.abs(point.X) <= halfX + pad
		and math.abs(point.Z) <= halfZ + pad
		and point.Y >= -halfY - pad
		and point.Y <= halfY + Catalog.StandHeight + pad
end

return Catalog

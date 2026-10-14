-- One catalog drives rolls, inventory, codex, odds, and collection totals.
-- Add new palette entries in ItemColors, then optionally override their rarity here.
local Palettes = require(script.Parent.Parent:WaitForChild("ItemColors"))
local Catalog = {
	Cost = 100,
	ModelName = "CosmeticRollStation", PartName = "RollZone",
	OpenDistance = 10, ServerDistance = 14, BillboardDistance = 45,
	Cooldown = 5,
	Defaults = {Gun = "Black", Rope = "Gray", Bomb = "Cyan"},
	Attributes = {Gun = "GrappleGunColor", Rope = "GrappleRopeColor", Bomb = "BombColor"},
	Rarities = {
		{Name = "Legendary", Chance = 0.001, Refund = 100, Color = Color3.fromRGB(255, 185, 49)},
		{Name = "Epic", Chance = 0.01, Refund = 75, Color = Color3.fromRGB(179, 110, 255)},
		{Name = "Rare", Chance = 0.10, Refund = 50, Color = Color3.fromRGB(78, 157, 255)},
		{Name = "Uncommon", Chance = 0.35, Refund = 25, Color = Color3.fromRGB(71, 203, 142)},
		{Name = "Common", Chance = 1, Refund = 10, Color = Color3.fromRGB(152, 169, 190)},
	},
	Items = {}, ById = {}, Pools = {},
}
local overrides = {
	Gun = {Rainbow = "Legendary", Teal = "Uncommon", Lime = "Uncommon", Pink = "Uncommon"},
	Rope = {Rainbow = "Legendary", Teal = "Uncommon", Lime = "Uncommon", Pink = "Uncommon"},
	Bomb = {Rainbow = "Legendary", Mint = "Uncommon", Pink = "Uncommon"},
}
local ranks = {}
for rank, rarity in ipairs(Catalog.Rarities) do
	ranks[rarity.Name] = rank
	Catalog.Pools[rarity.Name] = {}
end
for _, kind in ipairs({"Gun", "Rope", "Bomb"}) do
	local names = {}
	for name in pairs(Palettes[kind]) do
		-- Teal is only a legacy alias for Bomb/Mint; Gold is reserved for VIP.
		if name ~= "Gold" and name ~= "Banana" and not (kind == "Bomb" and name == "Teal") then
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
end
table.sort(Catalog.Items, function(a, b)
	if a.Rarity ~= b.Rarity then return ranks[a.Rarity] > ranks[b.Rarity] end
	if a.Name ~= b.Name then return a.Name < b.Name end
	return a.Kind < b.Kind
end)

function Catalog.Owns(player, kind, name)
	if kind == "Bomb" and name == "Banana" then return player:GetAttribute("Admin") == true end
	local item = Catalog.ById[tostring(kind) .. "_" .. tostring(name)]
	return item ~= nil and (item.Starter or player:GetAttribute("Owned_" .. item.Id) == true)
end

function Catalog.Count(player)
	local count = 0
	for _, item in ipairs(Catalog.Items) do
		if Catalog.Owns(player, item.Kind, item.Name) then count += 1 end
	end
	return count, #Catalog.Items
end

function Catalog.Rarity(name)
	return Catalog.Rarities[ranks[name]]
end

-- Independent highest-first checks. Empty tiers are skipped, never a dead roll.
function Catalog.Roll(random)
	for _, rarity in ipairs(Catalog.Rarities) do
		local pool = Catalog.Pools[rarity.Name]
		if #pool > 0 and (rarity.Name == "Common" or random:NextNumber() < rarity.Chance) then
			return pool[random:NextInteger(1, #pool)]
		end
	end
	error("The cosmetic catalog needs at least one rollable Common")
end

function Catalog.Odds()
	local remaining, tiers, items = 1, {}, {}
	for _, rarity in ipairs(Catalog.Rarities) do
		local pool = Catalog.Pools[rarity.Name]
		local chance = #pool > 0 and remaining * rarity.Chance or 0
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

-- Distance from the oriented zone surface; works for large or rotated zones.
function Catalog.Distance(part, position)
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	return Vector3.new(math.max(0, math.abs(point.X) - half.X),
		math.max(0, math.abs(point.Y) - half.Y), math.max(0, math.abs(point.Z) - half.Z)).Magnitude
end

return Catalog

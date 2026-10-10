-- Independent palettes: editing one item never changes the others.
local function originalPalette()
	return {
		Black = Color3.fromRGB(20, 20, 20), White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(220, 55, 55),
		Orange = Color3.fromRGB(242, 143, 43), Yellow = Color3.fromRGB(245, 220, 55), Green = Color3.fromRGB(65, 180, 90),
		Blue = Color3.fromRGB(55, 125, 230), Purple = Color3.fromRGB(145, 82, 210), Pink = Color3.fromRGB(240, 105, 175),
		Cyan = Color3.fromRGB(35, 210, 225), Teal = Color3.fromRGB(35, 155, 145),
	}
end
local palettes = {Gun = originalPalette(), Rope = originalPalette(), Bomb = {
	Red = Color3.fromRGB(255, 0, 0), Orange = Color3.fromRGB(255, 81, 0), Yellow = Color3.fromRGB(221, 255, 0),
	Green = Color3.fromRGB(0, 255, 60), Blue = Color3.fromRGB(38, 0, 255), Purple = Color3.fromRGB(72, 0, 255),
	Pink = Color3.fromRGB(240, 70, 255), White = Color3.fromRGB(255, 255, 255), Black = Color3.fromRGB(0, 0, 0),
	Cyan = Color3.fromRGB(0, 174, 255), Mint = Color3.fromRGB(34, 245, 94),
	Banana = Color3.fromRGB(255, 255, 0),
}}
-- Backward-compatible lookup for saved selections from before Mint was added.
palettes.Bomb.Teal = palettes.Bomb.Mint
-- Swatches are intentionally separate from material-adjusted equipment colors.
palettes.Swatches = {Gun = originalPalette(), Rope = originalPalette(), Bomb = table.clone(palettes.Bomb)}
palettes.Swatches.Bomb.Mint = Color3.fromRGB(152, 255, 180)
palettes.Swatches.Bomb.Teal = palettes.Swatches.Bomb.Mint
local function gunRopePalette()
	return {
		Red = Color3.fromRGB(255, 0, 0), Orange = Color3.fromRGB(255, 85, 0), Yellow = Color3.fromRGB(255, 204, 0),
		Green = Color3.fromRGB(16, 104, 0), Blue = Color3.fromRGB(0, 17, 255), Purple = Color3.fromRGB(97, 17, 167),
		Pink = Color3.fromRGB(255, 1, 230), White = Color3.fromRGB(255, 255, 255), Black = Color3.fromRGB(0, 0, 0),
		Gray = Color3.fromRGB(126, 126, 126), Cyan = Color3.fromRGB(0, 233, 254), Teal = Color3.fromRGB(74, 255, 164),
		Lime = Color3.fromRGB(47, 255, 0), Brown = Color3.fromRGB(70, 0, 1), Gold = Color3.fromRGB(232, 164, 38),
	}
end
palettes.Gun, palettes.Rope = gunRopePalette(), gunRopePalette()
for _, target in ipairs({"Gun", "Rope"}) do
	for name, color in pairs(palettes[target]) do
		if not palettes.Swatches[target][name] then palettes.Swatches[target][name] = color end
	end
end
palettes.Order = {"Black", "White", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Cyan", "Teal", "Gray", "Lime", "Brown", "Gold"}
-- Four close golds. Gun and rope shift through these the way rainbow shifts hues.
palettes.GoldStops = {
	Color3.fromRGB(176, 108, 24),
	Color3.fromRGB(232, 164, 38),
	Color3.fromRGB(255, 216, 102),
	Color3.fromRGB(255, 242, 186),
}
function palettes.GoldAt(phase)
	local stops = palettes.GoldStops
	local count = #stops
	local scaled = (phase % 1) * count
	local index = math.floor(scaled)
	return stops[index + 1]:Lerp(stops[(index + 1) % count + 1], scaled - index)
end
function palettes.BombRainbow(phase)
	local names = {"Red", "Orange", "Yellow", "Green", "Blue", "Purple"}
	local position = (phase % 1) * #names
	local index = math.floor(position)
	return palettes.Bomb[names[index + 1]]:Lerp(palettes.Bomb[names[(index + 1) % #names + 1]], position - index)
end
return palettes

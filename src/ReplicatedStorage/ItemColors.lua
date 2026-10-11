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
-- One full rainbow or gold loop. 0.1 is a 10 second cycle.
palettes.CycleSpeed = 0.1
-- Red through purple, then the last step blends straight back to red.
-- Hue stops at violet so pink is not its own stop on the way around.
local function sampleCycle(phase, stops)
	local count = #stops
	local scaled = (phase % 1) * count
	local index = math.floor(scaled)
	if index >= count then index = count - 1 end
	return stops[index + 1]:Lerp(stops[(index + 1) % count + 1], scaled - index)
end
palettes.RainbowStops = {
	Color3.fromHSV(0, 1, 1),
	Color3.fromHSV(0.08, 1, 1),
	Color3.fromHSV(0.15, 1, 1),
	Color3.fromHSV(0.33, 1, 1),
	Color3.fromHSV(0.50, 1, 1),
	Color3.fromHSV(0.66, 1, 1),
	Color3.fromHSV(0.75, 1, 1),
}
function palettes.RainbowAt(phase)
	return sampleCycle(phase, palettes.RainbowStops)
end
local bombRainbowStops = {
	palettes.Bomb.Red, palettes.Bomb.Orange, palettes.Bomb.Yellow,
	palettes.Bomb.Green, palettes.Bomb.Blue, palettes.Bomb.Purple,
}
function palettes.BombRainbow(phase)
	return sampleCycle(phase, bombRainbowStops)
end
return palettes

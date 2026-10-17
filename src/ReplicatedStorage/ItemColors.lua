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
	Banana = Color3.fromRGB(255, 255, 0), Gold = Color3.fromRGB(232, 164, 38),
	["Cartoon Bomb"] = Color3.fromRGB(94, 83, 98),
}}
-- Backward-compatible lookup for saved selections from before Mint was added.
palettes.Bomb.Teal = palettes.Bomb.Mint
-- Swatches are intentionally separate from material-adjusted equipment colors.
palettes.Swatches = {Gun = originalPalette(), Rope = originalPalette(), Bomb = table.clone(palettes.Bomb)}
local function gunRopePalette()
	return {
		Red = Color3.fromRGB(255, 0, 0), Orange = Color3.fromRGB(255, 85, 0), Yellow = Color3.fromRGB(255, 204, 0),
		Green = Color3.fromRGB(16, 104, 0), Blue = Color3.fromRGB(0, 17, 255), Purple = Color3.fromRGB(97, 17, 167),
		Pink = Color3.fromRGB(255, 1, 230), White = Color3.fromRGB(255, 255, 255), Black = Color3.fromRGB(0, 0, 0),
		Gray = Color3.fromRGB(126, 126, 126), Cyan = Color3.fromRGB(0, 233, 254), Mint = Color3.fromRGB(74, 255, 164),
		Lime = Color3.fromRGB(47, 255, 0), Brown = Color3.fromRGB(70, 0, 1), Gold = Color3.fromRGB(232, 164, 38),
	}
end
palettes.Gun, palettes.Rope = gunRopePalette(), gunRopePalette()
palettes.Rope.Chain = Color3.fromRGB(184, 184, 184)
for _, target in ipairs({"Gun", "Rope"}) do
	for name, color in pairs(palettes[target]) do
		if not palettes.Swatches[target][name] then palettes.Swatches[target][name] = color end
	end
end
-- Neon equipment colors, base icon swatches, and icon glows are independent.
palettes.NeonRopes = {}
palettes.NeonGuns = {}
palettes.NeonGunPartColors = {}
-- Icon halos use clear named colors; beam RGBs are tuned separately for brightness 10.
palettes.NeonIconGlows = {
	["Neon Red"] = Color3.fromRGB(255, 64, 73),
	["Neon Orange"] = Color3.fromRGB(255, 154, 51),
	["Neon Yellow"] = Color3.fromRGB(255, 228, 64),
	["Neon Green"] = Color3.fromRGB(72, 255, 100),
	["Neon Blue"] = Color3.fromRGB(72, 120, 255),
	["Neon Purple"] = Color3.fromRGB(165, 89, 255),
	["Neon Pink"] = Color3.fromRGB(255, 88, 200),
	["Neon Cyan"] = Color3.fromRGB(70, 230, 255),
	["Neon Mint"] = Color3.fromRGB(80, 255, 190),
}
-- Name, base icon swatch, rope beam RGB, then Neon gun part RGB.
for _, entry in ipairs({
	{"Red", "Red", 255, 53, 53, 255, 115, 117},
	{"Orange", "Orange", 255, 86, 52, 255, 132, 101},
	{"Yellow", "Yellow", 255, 140, 46, 255, 209, 102},
	{"Green", "Green", 50, 249, 50, 91, 185, 89},
	{"Blue", "Blue", 49, 49, 255, 98, 106, 255},
	{"Purple", "Purple", 95, 52, 239, 130, 99, 255},
	{"Pink", "Pink", 255, 44, 209, 251, 149, 255},
	{"Cyan", "Cyan", 39, 218, 254, 98, 195, 255},
	{"Mint", "Mint", 67, 255, 89, 125, 255, 162},
}) do
	local baseName = entry[2]
	local name = "Neon " .. entry[1]
	palettes.NeonRopes[name] = baseName
	palettes.NeonGuns[name] = baseName
	palettes.Rope[name] = Color3.fromRGB(entry[3], entry[4], entry[5])
	palettes.Gun[name] = palettes.Rope[name]
	palettes.NeonGunPartColors[name] = Color3.fromRGB(entry[6], entry[7], entry[8])
	palettes.Swatches.Rope[name] = palettes.Swatches.Rope[baseName]
	palettes.Swatches.Gun[name] = palettes.Swatches.Gun[baseName]
end
-- Rare gun finishes. Material names are resolved to Enum.Material by the server.
palettes.RareGuns = {
	Sandstorm = {Color = Color3.fromRGB(198, 168, 138), Material = "Cobblestone"},
	Jungle = {Color = Color3.fromRGB(62, 121, 44), Material = "Cobblestone"},
	Ice = {Color = Color3.fromRGB(6, 166, 198), Material = "Ice", Transparency = 0.15},
	Autumn = {Color = Color3.fromRGB(255, 119, 0), Material = "LeafyGrass"},
	Brick = {Color = Color3.fromRGB(180, 4, 7), Material = "Brick"},
	Panther = {Color = Color3.fromRGB(0, 0, 0), Material = "Asphalt"},
	Rust = {Color = Color3.fromRGB(122, 60, 60), Material = "CorrodedMetal"},
	Lava = {Color = Color3.fromRGB(226, 123, 38), Material = "CrackedLava"},
	Crimson = {Color = Color3.fromRGB(255, 0, 4), Material = "CrackedLava"},
	["Baby Pink"] = {Color = Color3.fromRGB(255, 201, 232), Material = "Fabric"},
	["Baby Blue"] = {Color = Color3.fromRGB(143, 255, 251), Material = "Fabric"},
	Nebula = {Color = Color3.fromRGB(47, 0, 148), Material = "Grass"},
	Construction = {Color = Color3.fromRGB(255, 213, 0), Material = "Pavement"},
	["Pink Venom"] = {Color = Color3.fromRGB(255, 0, 208), Material = "CrackedLava"},
	Grass = {Color = Color3.fromRGB(31, 208, 0), Material = "Grass"},
	Wooden = {Color = Color3.fromRGB(141, 71, 66), Material = "Wood"},
	Ocean = {Color = Color3.fromRGB(0, 123, 255), Material = "Marble"},
}
for name, finish in pairs(palettes.RareGuns) do
	palettes.Gun[name] = finish.Color
	palettes.Swatches.Gun[name] = finish.Color
end
-- Shared names use the gun and rope card. Bomb-only cards stay. Part colors stay on palettes.Bomb.
for name, color in pairs(palettes.Swatches.Gun) do
	if palettes.Swatches.Bomb[name] then palettes.Swatches.Bomb[name] = color end
end
-- Use a softer jade swatch for the icon; the in-game bomb stays neon.
palettes.Swatches.Bomb.Mint = Color3.fromRGB(32, 205, 137)
palettes.Order = {"Black", "White", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Cyan", "Mint", "Gray", "Lime", "Brown", "Chain", "Neon Red", "Neon Orange", "Neon Yellow", "Neon Green", "Neon Blue", "Neon Purple", "Neon Pink", "Neon Cyan", "Neon Mint", "Gold"}
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

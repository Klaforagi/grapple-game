local Palettes = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemColors"))
local RunService = game:GetService("RunService")
local beams = {}
local parts = {}
local function watch(instance)
	if instance:IsA("Beam") then beams[instance] = {active = false, original = instance.Color} end
	if instance:IsA("BasePart") and (instance:GetAttribute("RainbowPart") ~= nil
		or instance:FindFirstAncestorOfClass("Tool")) then
		parts[instance] = {active = false, original = instance.Color}
	end
end
workspace.DescendantAdded:Connect(watch)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < 1 / 30 then return end
	elapsed = 0
	local hue = (workspace:GetServerTimeNow() * Palettes.CycleSpeed) % 1
	for part, state in pairs(parts) do
		if not part:IsDescendantOf(workspace) or not part:GetAttribute("RainbowPart") then
			if state.active then part.Color = part:GetAttribute("SolidPartColor") or state.original end
			state.active = false
			if not part:IsDescendantOf(workspace) then parts[part] = nil end
		else
			if not state.active then state.original = part.Color end
			state.active = true
			local palette = part:GetAttribute("RainbowPalette")
			part.Color = palette == "Bomb" and Palettes.BombRainbow(hue)
				or palette == "Gold" and Palettes.GoldAt(hue)
				or Palettes.RainbowAt(hue)
		end
	end
	local sequence, goldSequence
	for beam, state in pairs(beams) do
		if not beam:IsDescendantOf(workspace) then
			if state.active then
				local color = beam:GetAttribute("SolidRopeColor")
				beam.Color = color and ColorSequence.new(color) or state.original
			end
			beams[beam] = nil
		elseif beam:GetAttribute("RainbowRope") then
			if not state.active then state.original = beam.Color end
			state.active = true
			if beam.Enabled then
				local phase = workspace:GetServerTimeNow() * Palettes.CycleSpeed
				local gold = beam:GetAttribute("RainbowPalette") == "Gold"
				if gold and not goldSequence then
					local points = {}
					local count = #Palettes.GoldStops
					for index = 0, count do
						local position = index / count
						table.insert(points, ColorSequenceKeypoint.new(position, Palettes.GoldAt((position - phase) % 1)))
					end
					goldSequence = ColorSequence.new(points)
				elseif not gold and not sequence then
					local points = {}
					for index = 0, 18 do
						local position = index / 18
						table.insert(points, ColorSequenceKeypoint.new(position, Palettes.RainbowAt((position - phase) % 1)))
					end
					sequence = ColorSequence.new(points)
				end
				beam.Segments = math.max(beam.Segments, 24)
				beam.Color = gold and goldSequence or sequence
			end
		elseif state.active then
			local color = beam:GetAttribute("SolidRopeColor")
			beam.Color = color and ColorSequence.new(color) or state.original
			state.active = false
		end
	end
end)

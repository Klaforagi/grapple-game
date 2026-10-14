local Ui = require(script.Parent:WaitForChild("CollectionUi"))
local Style = {
	Ink = Color3.fromRGB(13, 17, 27), Text = Color3.fromRGB(242, 239, 255),
	Muted = Color3.fromRGB(178, 178, 205), Accent = Color3.fromRGB(92, 229, 184),
	Panel = Color3.fromRGB(70, 58, 99), Header = Color3.fromRGB(99, 78, 138),
	Slot = Color3.fromRGB(29, 32, 48), ButtonColor = Color3.fromRGB(76, 78, 108),
}
local make, round = Ui.Make, Ui.Round
local ink, white = Style.Ink, Style.Text

-- Dark outlines and diagonal highlights give the panels a chunky toy-like finish.
function Style.Surface(parent, color, radius)
	parent.BackgroundColor3 = Color3.new(1, 1, 1)
	parent.BorderSizePixel = 0
	round(parent, radius or 6)
	make("UIGradient", parent, {Rotation = 28, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(white, 0.18)),
		ColorSequenceKeypoint.new(0.44, color:Lerp(white, 0.06)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(1, color:Lerp(ink, 0.30)),
	})})
	return make("UIStroke", parent, {Color = ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end

function Style.Label(parent, value, position, size, fontSize, color)
	local label = Ui.Text(parent, value, position, size, fontSize, color or Style.Text)
	label.TextStrokeColor3, label.TextStrokeTransparency = Style.Ink, 0.45
	return label
end

function Style.Button(parent, value, position, size, color)
	local button = make("TextButton", parent, {Text = value, Position = position, Size = size,
		TextColor3 = Style.Text, TextSize = 18, Font = Enum.Font.GothamBlack,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.5, AutoButtonColor = true,
		BackgroundTransparency = 1, BorderSizePixel = 0})
	round(button, 6)
	-- UIGradient also tints a TextButton's own text. Keep the decorated
	-- background and foreground label separate so text stays bright.
	local background = make("Frame", button, {Name = "Surface", Size = UDim2.fromScale(1, 1)})
	local stroke = Style.Surface(background, color or Style.ButtonColor)
	stroke.Parent = button
	local foreground = make("TextLabel", button, {Name = "Label", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2})
	for _, property in ipairs({"Text", "TextColor3", "TextSize", "Font", "TextTransparency", "TextStrokeColor3",
		"TextStrokeTransparency", "TextXAlignment", "TextYAlignment", "TextScaled"}) do
		foreground[property] = button[property]
		button:GetPropertyChangedSignal(property):Connect(function() foreground[property] = button[property] end)
	end
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		background.ZIndex, foreground.ZIndex = button.ZIndex, button.ZIndex + 1
	end)
	return button
end

function Style.Icon(parent, item)
	local function piece(position, size, color, radius)
		local frame = make("Frame", parent, {Position = position, Size = size, BorderSizePixel = 0,
			BackgroundColor3 = color or item.Color})
		round(frame, radius or 8)
		if not color then Ui.Paint(frame, item) end
		if not color and item.Kind ~= "Rope" then
			make("UIStroke", frame, {Color = Style.Muted, Thickness = 1.2, Transparency = 0.45})
		end
		return frame
	end
	if item.Kind == "Bomb" then
		-- The in-game bomb is a neon sphere with soft bloom and a luminous rim.
		for layer = 3, 1, -1 do
			local diameter = 70 + layer * 8
			local glow = piece(UDim2.fromOffset(61 - diameter / 2, 50 - diameter / 2),
				UDim2.fromOffset(diameter, diameter), item.Color, diameter / 2)
			glow.BackgroundTransparency = 0.80 + layer * 0.045
		end
		local orb = piece(UDim2.fromOffset(26, 15), UDim2.fromOffset(70, 70), white, 35)
		Ui.Paint(orb, item)
		if item.Name ~= "Rainbow" then
			orb.BackgroundColor3 = Color3.new(1, 1, 1)
			make("UIGradient", orb, {Rotation = 50, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, item.Color:Lerp(white, 0.55)),
				ColorSequenceKeypoint.new(0.45, item.Color),
				ColorSequenceKeypoint.new(1, item.Color:Lerp(ink, 0.35)),
			})})
		end
		local rim = make("UIStroke", orb, {Color = item.Color:Lerp(white, 0.5), Thickness = 1.8, Transparency = 0.2})
		if item.Name == "Rainbow" then
			rim.Color, rim.Transparency = Color3.new(1, 1, 1), 0
			make("UIGradient", rim, {Rotation = 25, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 45, 45)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 145, 0)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 230, 0)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(35, 230, 75)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(40, 100, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 50, 255)),
			})})
		end
	elseif item.Kind == "Gun" then
		piece(UDim2.fromOffset(26, 45), UDim2.fromOffset(23, 46), nil, 6).Rotation = 14
		piece(UDim2.fromOffset(17, 25), UDim2.fromOffset(83, 31))
		piece(UDim2.fromOffset(91, 29), UDim2.fromOffset(14, 23), ink, 4)
		piece(UDim2.fromOffset(26, 30), UDim2.fromOffset(48, 6), white, 3).BackgroundTransparency = 0.55
	else
		local rainbowLoops = item.Name == "Rainbow" and {
			ColorSequence.new(Color3.fromRGB(255, 45, 45), Color3.fromRGB(255, 145, 0)),
			ColorSequence.new(Color3.fromRGB(255, 230, 0), Color3.fromRGB(35, 230, 75)),
			ColorSequence.new(Color3.fromRGB(40, 100, 255), Color3.fromRGB(175, 50, 255)),
		}
		for i = 0, 2 do
			local loop = piece(UDim2.fromOffset(30 + i * 6, 20 + i * 9), UDim2.fromOffset(56, 46), white, 24)
			loop.BackgroundTransparency = 1
			local stroke = make("UIStroke", loop, {Thickness = 7, Color = rainbowLoops and Color3.new(1, 1, 1) or item.Color})
			if rainbowLoops then
				make("UIGradient", stroke, {Rotation = 45, Color = rainbowLoops[i + 1]})
			end
		end
	end
end


return Style

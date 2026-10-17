local Ui = require(script.Parent:WaitForChild("CollectionUi"))
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Palettes = require(script.Parent.Parent:WaitForChild("ItemColors"))
local Style = table.clone(require(script.Parent:WaitForChild("UiTheme")).Current)
local make, round = Ui.Make, Ui.Round
local ink, white = Style.Ink, Style.Text

-- Dark outlines and diagonal highlights give the panels a chunky toy-like finish.
function Style.Sequence(color)
	local gradient
	if color == Style.Header then gradient = Style.HeaderGradient
	elseif color == Style.Slot then gradient = Style.SlotGradient end
	if color == Style.CoinBackground then gradient = Style.CoinGradient or gradient end
	local light = gradient and gradient[1] or 0.18
	local middle = gradient and gradient[2] or 0.06
	local shade = gradient and gradient[3] or 0.30
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(white, light)),
		ColorSequenceKeypoint.new(0.44, color:Lerp(white, middle)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(1, color:Lerp(ink, shade)),
	})
end

function Style.Surface(parent, color, radius)
	parent.BackgroundColor3 = Color3.new(1, 1, 1)
	parent.BackgroundTransparency = 0
	parent.BorderSizePixel = 0
	round(parent, radius or 6)
	make("UIGradient", parent, {Rotation = 28, Color = Style.Sequence(color)})
	return make("UIStroke", parent, {Color = ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end

function Style.Recolor(parent, color)
	local surface = parent:FindFirstChild("Surface") or parent
	local gradient = surface:FindFirstChildOfClass("UIGradient")
	if gradient then gradient.Color = Style.Sequence(color) end
end

-- A full-size plate for a control that already draws its own text or icons.
function Style.Backdrop(parent, color, radius)
	parent.BackgroundTransparency = 1
	parent.BorderSizePixel = 0
	local background = make("Frame", parent, {
		Name = "Surface", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
		ZIndex = parent.ZIndex, Active = false,
	})
	local stroke = Style.Surface(background, color or Style.ButtonColor, radius or 6)
	stroke.Parent = parent
	return background
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
	local special = item.Name == "Rainbow" or item.Name == "Gold"
	local neon = (item.Kind == "Rope" and Palettes.NeonRopes[item.Name] ~= nil)
		or (item.Kind == "Gun" and Palettes.NeonGuns[item.Name] ~= nil)
	local neonColor = neon and Palettes.NeonIconGlows[item.Name]
	if neon then
		-- Colored outer glow around a near-white core, using the same rope image.
		for _, layer in ipairs({
			{Scale = 1.22, Transparency = 0.72},
			{Scale = 1.09, Transparency = 0.42},
		}) do
			make("ImageLabel", parent, {
				Name = "NeonGlow", BackgroundTransparency = 1, BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(layer.Scale, layer.Scale), Image = Assets[item.Kind],
				ImageColor3 = neonColor,
				ImageTransparency = layer.Transparency, ScaleType = Enum.ScaleType.Fit,
				ZIndex = parent.ZIndex + 1,
			})
		end
	end
	local image = make("ImageLabel", parent, {
		Name = "CosmeticIcon", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), Image = Assets[item.Kind],
		ImageColor3 = special and Color3.new(1, 1, 1)
			or neon and neonColor:Lerp(Color3.new(1, 1, 1), 0.8) or item.Color,
		ScaleType = Enum.ScaleType.Fit, ZIndex = parent.ZIndex + (neon and 2 or 1),
	})
	if special then
		local points = {}
		local stops = item.Name == "Gold" and Palettes.GoldStops or Palettes.RainbowStops
		-- Keep the full spectrum inside the image's opaque shape instead of
		-- losing red and purple in its transparent outer padding.
		local inset = item.Name == "Rainbow" and 0.16 or 0
		if inset > 0 then points[1] = ColorSequenceKeypoint.new(0, stops[1]) end
		for index, color in ipairs(stops) do
			points[#points + 1] = ColorSequenceKeypoint.new(inset + (index - 1) / (#stops - 1) * (1 - 2 * inset), color)
		end
		if inset > 0 then points[#points + 1] = ColorSequenceKeypoint.new(1, stops[#stops]) end
		make("UIGradient", image, {Color = ColorSequence.new(points), Rotation = 0})
	end
	return image
end


return Style

local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
local Palettes = require(script.Parent.Parent:WaitForChild("ItemColors"))
local Players = game:GetService("Players")
local Ui = {}

function Ui.Make(class, parent, props)
	local object = Instance.new(class)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end
local make = Ui.Make
function Ui.Round(parent, radius)
	return make("UICorner", parent, {CornerRadius = UDim.new(0, radius or 14)})
end
function Ui.Text(parent, text, position, size, fontSize, color)
	return make("TextLabel", parent, {BackgroundTransparency = 1, Text = text,
		Position = position, Size = size, Font = Enum.Font.GothamBold, TextSize = fontSize or 16,
		TextColor3 = color or Color3.fromRGB(41, 57, 82), TextXAlignment = Enum.TextXAlignment.Left})
end
function Ui.Paint(parent, item)
	parent.BackgroundColor3 = item.Color
	if item.Name == "Rainbow" then
		local points = {}
		for i = 0, 12 do points[i + 1] = ColorSequenceKeypoint.new(i / 12, Palettes.RainbowAt(i / 12)) end
		make("UIGradient", parent, {Color = ColorSequence.new(points), Rotation = 25})
	end
end
function Ui.OwnedText(player)
	local owned, total = Catalog.Count(player)
	return string.format("Owned %d out of %d", owned, total)
end

function Ui.PopulateCodex(window)
	local player = Players.LocalPlayer
	local _, odds = Catalog.Odds()
	local ownedLabel = Ui.Text(window, Ui.OwnedText(player), UDim2.fromOffset(16, 42), UDim2.new(1, -32, 0, 22), 16, Color3.fromRGB(129, 233, 187))
	local scroll = make("ScrollingFrame", window, {Name = "Items", Position = UDim2.fromOffset(12, 76),
		Size = UDim2.new(1, -24, 1, -88), BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y})
	make("UIListLayout", scroll, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
	local rows, order = {}, 0
	for _, kind in ipairs({"Gun", "Rope", "Bomb"}) do
		order += 1
		local header = Ui.Text(scroll, string.upper(kind), UDim2.new(), UDim2.new(1, -8, 0, 26), 14, Color3.fromRGB(212, 228, 250))
		header.LayoutOrder = order
		for _, item in ipairs(Catalog.Items) do
			if item.Kind ~= kind then continue end
			order += 1
			local rarity = Catalog.Rarity(item.Rarity)
			local row = make("Frame", scroll, {Name = item.Id, Size = UDim2.new(1, -8, 0, 56), LayoutOrder = order,
				BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(29, 40, 54)})
			Ui.Round(row, 8)
			local swatch = make("Frame", row, {Position = UDim2.fromOffset(8, 10), Size = UDim2.fromOffset(32, 36), BorderSizePixel = 0})
			Ui.Round(swatch, 8) Ui.Paint(swatch, item)
			local name = Ui.Text(row, item.Name, UDim2.fromOffset(48, 5), UDim2.new(1, -116, 0, 23), 15, Color3.new(1, 1, 1))
			local detail = item.Starter and "Common  /  Starter" or string.format("%s  /  %.4f%% per roll", item.Rarity, (odds[item.Id] or 0) * 100)
			Ui.Text(row, detail, UDim2.fromOffset(48, 29), UDim2.new(1, -52, 0, 19), 11, rarity.Color)
			local status = Ui.Text(row, "", UDim2.new(1, -66, 0, 8), UDim2.fromOffset(58, 20), 11)
			status.TextXAlignment = Enum.TextXAlignment.Right
			table.insert(rows, {Item = item, Name = name, Status = status})
		end
	end
	local function refresh()
		ownedLabel.Text = Ui.OwnedText(player)
		for _, row in ipairs(rows) do
			local owned = Catalog.Owns(player, row.Item.Kind, row.Item.Name)
			row.Name.TextTransparency = owned and 0 or 0.4
			row.Status.Text = owned and "Owned" or "Locked"
			row.Status.TextColor3 = owned and Color3.fromRGB(129, 233, 187) or Color3.fromRGB(154, 169, 192)
		end
	end
	refresh()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "CollectionLoaded" then refresh() end
	end)
end

function Ui.CreateInventory(parent, equipRemote)
	local player = Players.LocalPlayer
	local selectedKind = "Gun"
	local panel = make("Frame", parent, {Name = "GrappleInventory", Position = UDim2.fromOffset(54, 22),
		Size = UDim2.fromOffset(240, 300), BackgroundColor3 = Color3.fromRGB(39, 51, 65), BorderSizePixel = 0, Visible = false})
	Ui.Round(panel, 12)
	make("UIStroke", panel, {Color = Color3.new(1, 1, 1), Thickness = 0.5})
	local scroll = make("ScrollingFrame", panel, {Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 1, -60),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y})
	make("UIGridLayout", scroll, {CellSize = UDim2.fromOffset(66, 64), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder})
	local tabs = {}
	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		for kind, tab in pairs(tabs) do
			tab.BackgroundColor3 = kind == selectedKind and Color3.fromRGB(65, 133, 244) or Color3.fromRGB(61, 77, 96)
		end
		local items = {}
		for _, item in ipairs(Catalog.Items) do
			if item.Kind == selectedKind and Catalog.Owns(player, item.Kind, item.Name) then table.insert(items, item) end
		end
		if selectedKind == "Bomb" and Catalog.Owns(player, "Bomb", "Banana") then
			table.insert(items, {Id = "Bomb_Banana", Kind = "Bomb", Name = "Banana", Rarity = "Common", Color = Palettes.Swatches.Bomb.Banana, Admin = true})
		end
		for index, item in ipairs(items) do
			local button = make("TextButton", scroll, {Name = item.Id, Text = "", LayoutOrder = index, BackgroundColor3 = Color3.fromRGB(29, 40, 54), BorderSizePixel = 0})
			Ui.Round(button, 8)
			local swatch = make("Frame", button, {Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(56, 29), BorderSizePixel = 0})
			Ui.Round(swatch, 6) Ui.Paint(swatch, item)
			local equipped = player:GetAttribute(Catalog.Attributes[item.Kind]) == item.Name
			make("UIStroke", button, {Thickness = equipped and 2 or 1, Color = equipped and Color3.fromRGB(129, 233, 187) or Color3.fromRGB(68, 87, 110)})
			local name = Ui.Text(button, item.Name, UDim2.fromOffset(1, 35), UDim2.fromOffset(64, 15), 10, Color3.new(1, 1, 1))
			name.TextXAlignment = Enum.TextXAlignment.Center
			local rarity = Ui.Text(button, item.Admin and "Admin" or item.Rarity, UDim2.fromOffset(1, 50), UDim2.fromOffset(64, 12), 8, Catalog.Rarity(item.Rarity).Color)
			rarity.TextXAlignment = Enum.TextXAlignment.Center
			button.Activated:Connect(function() equipRemote:FireServer(item.Kind, item.Name) end)
		end
		panel.Size = UDim2.fromOffset(240, math.min(340, 60 + math.max(1, math.ceil(#items / 3)) * 70))
	end
	for index, kind in ipairs({"Gun", "Rope", "Bomb"}) do
		local tab = make("TextButton", panel, {Text = kind, Position = UDim2.fromOffset(10 + (index - 1) * 74, 10),
			Size = UDim2.fromOffset(70, 30), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0})
		Ui.Round(tab, 8)
		tabs[kind] = tab
		tab.Activated:Connect(function() selectedKind = kind refresh() end)
	end
	refresh()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "Admin" or key == "CollectionLoaded"
			or key == Catalog.Attributes[selectedKind] then refresh() end
	end)
	return panel
end

return Ui

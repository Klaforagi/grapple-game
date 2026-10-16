local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
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
function Ui.OwnedText(player, kind)
	local owned, total = Catalog.Count(player, kind)
	return string.format("Owned %d out of %d", owned, total)
end

function Ui.PopulateCodex(window)
	local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
	local player = Players.LocalPlayer
	local _, odds = Catalog.Odds(Catalog.LuckMultiplier(player))
	local ownedLabel = Ui.Text(window, Ui.OwnedText(player), UDim2.fromOffset(16, 58), UDim2.new(1, -32, 0, 22), 16, Style.Accent)
	ownedLabel.TextStrokeColor3, ownedLabel.TextStrokeTransparency = Style.Ink, 0.45
	local luckLabel = Ui.Text(window, "", UDim2.fromOffset(16, 80), UDim2.new(1, -32, 0, 20), 13, Style.Muted)
	luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckLabel.TextStrokeColor3, luckLabel.TextStrokeTransparency = Style.Ink, 0.45
	local scroll = make("ScrollingFrame", window, {Name = "Items", Position = UDim2.fromOffset(12, 108),
		Size = UDim2.new(1, -24, 1, -120), BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6,
		ScrollBarImageColor3 = Style.Text, ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always})
	make("UIPadding", scroll, {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8),
	})
	make("UIListLayout", scroll, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
	local rows, order = {}, 0
	for _, kind in ipairs({"Gun", "Rope", "Bomb"}) do
		order += 1
		local header = Ui.Text(scroll, string.upper(kind), UDim2.new(), UDim2.new(1, 0, 0, 26), 14, Style.Text)
		header.LayoutOrder = order
		header.TextStrokeColor3, header.TextStrokeTransparency = Style.Ink, 0.45
		local listed = {}
		for _, item in ipairs(Catalog.Items) do
			if item.Kind ~= kind then continue end
			if item.Starter then table.insert(listed, 1, item) else table.insert(listed, item) end
		end
		for _, item in ipairs(listed) do
			order += 1
			local rarity = Catalog.Rarity(item.Rarity)
			local row = make("Frame", scroll, {Name = item.Id, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = order, BorderSizePixel = 0})
			Style.Surface(row, Style.Slot, 6)
			local art = make("Frame", row, {Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(42, 42), BackgroundTransparency = 1, BorderSizePixel = 0})
			Style.Icon(art, item)
			local name = Ui.Text(row, item.Name, UDim2.fromOffset(56, 5), UDim2.new(1, -124, 0, 23), 15, Style.Text)
			name.TextStrokeColor3, name.TextStrokeTransparency = Style.Ink, 0.45
			local detail = item.Vip and (item.Rarity .. "  /  VIP")
				or item.Starter and (item.Rarity .. "  /  Starter")
				or string.format("%s  /  %.4f%% per roll", item.Rarity, (odds[item.Id] or 0) * 100)
			local detailLabel = Ui.Text(row, detail, UDim2.fromOffset(56, 29), UDim2.new(1, -60, 0, 19), 11, rarity.Color)
			detailLabel.TextStrokeColor3, detailLabel.TextStrokeTransparency = Style.Ink, 0.55
			local status = Ui.Text(row, "", UDim2.new(1, -66, 0, 8), UDim2.fromOffset(58, 20), 11)
			status.TextXAlignment = Enum.TextXAlignment.Right
			status.TextStrokeColor3, status.TextStrokeTransparency = Style.Ink, 0.45
			table.insert(rows, {Item = item, Name = name, Detail = detailLabel, Status = status})
		end
	end
	local function refresh()
		local luck = Catalog.LuckMultiplier(player)
		local _, currentOdds = Catalog.Odds(luck)
		luckLabel.Text = luck > 1 and "2x Luck active" or "2x Luck not active"
		luckLabel.TextColor3 = luck > 1 and Style.Accent or Color3.fromRGB(195, 76, 87)
		ownedLabel.Text = Ui.OwnedText(player)
		for _, row in ipairs(rows) do
			local owned = Catalog.Owns(player, row.Item.Kind, row.Item.Name)
			row.Name.TextTransparency = owned and 0 or 0.4
			if not row.Item.Starter and not row.Item.Vip then
				row.Detail.Text = string.format("%s  /  %.4f%% per roll", row.Item.Rarity, (currentOdds[row.Item.Id] or 0) * 100)
			end
			row.Status.Text = owned and "Owned" or "Missing"
			row.Status.TextColor3 = owned and Style.Accent or Style.Muted
		end
	end
	refresh()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "CollectionLoaded" or key == "TestPass_2xLuck" or key == "TestPass_VIP" then refresh() end
	end)
end

function Ui.CreateInventory(parent, equipRemote, onClose)
	return require(script.Parent:WaitForChild("CosmeticInventoryUi")).Create(parent, equipRemote, onClose)
end
return Ui

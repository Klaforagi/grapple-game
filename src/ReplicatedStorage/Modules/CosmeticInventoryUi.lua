local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
local Ui = require(script.Parent:WaitForChild("CollectionUi"))
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local Palettes = require(script.Parent.Parent:WaitForChild("ItemColors"))
local make, label = Ui.Make, Style.Label
local Inventory = {}

function Inventory.Create(parent, equipRemote, onClose)
	local player = Players.LocalPlayer
	local panel = make("Frame", parent, {Name = "GrappleInventory", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 524), Visible = false, ZIndex = 20})
	Style.Surface(panel, Style.Panel, 8)
	local scale = make("UIScale", panel, {Scale = 1})
	local header = make("Frame", panel, {Size = UDim2.new(1, 0, 0, 68)})
	Style.Surface(header, Style.Header, 8)
	label(header, "INVENTORY", UDim2.fromOffset(22, 15), UDim2.fromOffset(350, 38), 26)
	local counter = label(header, "", UDim2.fromOffset(510, 18), UDim2.fromOffset(232, 32), 16, Style.Accent)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	local close = Style.Button(header, "X", UDim2.fromOffset(758, 12), UDim2.fromOffset(46, 44), Color3.fromRGB(195, 76, 87))
	close.Activated:Connect(onClose)
	local scroll = make("ScrollingFrame", panel, {Position = UDim2.fromOffset(18, 132), Size = UDim2.fromOffset(518, 372),
		BackgroundColor3 = Style.Ink, BackgroundTransparency = 0.28, BorderSizePixel = 0, ScrollBarThickness = 5,
		ScrollBarImageColor3 = Style.Muted, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y})
	make("UIPadding", scroll, {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)})
	make("UIGridLayout", scroll, {CellSize = UDim2.fromOffset(90, 100), CellPadding = UDim2.fromOffset(11, 11), SortOrder = Enum.SortOrder.LayoutOrder})
	local preview = make("Frame", panel, {Position = UDim2.fromOffset(554, 86), Size = UDim2.fromOffset(248, 282)})
	Style.Surface(preview, Style.Slot, 6)
	local art = make("Frame", preview, {Position = UDim2.fromOffset(50, 16), Size = UDim2.fromOffset(122, 100), BackgroundTransparency = 1})
	make("UIScale", art, {Scale = 1.2})
	local name = label(preview, "", UDim2.fromOffset(10, 158), UDim2.fromOffset(228, 32), 25)
	name.TextXAlignment = Enum.TextXAlignment.Center
	local category = label(preview, "", UDim2.fromOffset(10, 195), UDim2.fromOffset(228, 22), 14, Style.Muted)
	category.TextXAlignment = Enum.TextXAlignment.Center
	local rarity = label(preview, "", UDim2.fromOffset(10, 220), UDim2.fromOffset(228, 22), 16)
	rarity.TextXAlignment = Enum.TextXAlignment.Center
	local quantity = label(preview, "", UDim2.fromOffset(10, 249), UDim2.fromOffset(228, 20), 13, Style.Muted)
	quantity.TextXAlignment = Enum.TextXAlignment.Center
	local equip = Style.Button(panel, "EQUIP", UDim2.fromOffset(554, 384), UDim2.fromOffset(248, 44), Color3.fromRGB(62, 165, 110))
	local sell = Style.Button(panel, "SELL", UDim2.fromOffset(554, 440), UDim2.fromOffset(248, 44), Color3.fromRGB(194, 126, 48))
	local saleNote = label(panel, "", UDim2.fromOffset(554, 489), UDim2.fromOffset(248, 30), 11, Style.Muted)
	saleNote.TextWrapped, saleNote.TextXAlignment = true, Enum.TextXAlignment.Center
	local selected, selectedKind = nil, "All"
	local confirmItem, saleRequest, saleBusy = nil, nil, false
	local tabs, cards = {}, {}
	local function updateSelection()
		sell.Visible = selected ~= nil and not selected.Starter and not selected.Admin
		if sell.Visible then
			sell.Text = saleBusy and "SELLING..." or saleRequest and "RETRY" or confirmItem == selected.Id and "CONFIRM"
				or string.format("SELL / %d COINS", Catalog.SellPrices[selected.Rarity])
			sell.AutoButtonColor = not saleBusy
		end
		for id, entry in pairs(cards) do
			entry.Stroke.Color = selected and selected.Id == id and Style.Text or Style.Ink
			entry.Stroke.Thickness = selected and selected.Id == id and 3 or 2
		end
		for _, child in ipairs(art:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		if not selected then
			name.Text, category.Text, rarity.Text, quantity.Text = "No items yet", "", "", ""
			equip.Text, equip.Active, equip.AutoButtonColor = "EQUIP", false, false
			return
		end
		Style.Icon(art, selected)
		name.Text, category.Text = selected.Name, string.upper(selected.Kind)
		rarity.Text = selected.Admin and "ADMIN" or string.upper(selected.Rarity)
		rarity.TextColor3 = Catalog.Rarity(selected.Rarity).Color
		local copies = Catalog.Copies(player, selected.Kind, selected.Name)
		quantity.Text = copies == 1 and "Owned" or string.format("Owned x%d", copies)
		local equipped = player:GetAttribute(Catalog.Attributes[selected.Kind]) == selected.Name
		equip.Text, equip.Active, equip.AutoButtonColor = equipped and "EQUIPPED" or "EQUIP", not equipped, not equipped
	end
	local function refresh()
		counter.Text = Ui.OwnedText(player, selectedKind)
		for _, child in ipairs(scroll:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		table.clear(cards)
		local items = {}
		for _, item in ipairs(Catalog.Items) do
			if (selectedKind == "All" or item.Kind == selectedKind) and Catalog.Owns(player, item.Kind, item.Name) then table.insert(items, item) end
		end
		if (selectedKind == "All" or selectedKind == "Bomb") and Catalog.Owns(player, "Bomb", "Banana") then
			table.insert(items, {Id = "Bomb_Banana", Kind = "Bomb", Name = "Banana", Rarity = "Common", Color = Palettes.Swatches.Bomb.Banana, Admin = true})
		end
		local found = false
		for _, item in ipairs(items) do if selected and selected.Id == item.Id then selected = item found = true break end end
		if saleRequest then selected = Catalog.ById[saleRequest.itemId]
		elseif not found then selected = items[1] end
		for index = 1, math.max(20, #items) do
			local item = items[index]
			local card = make(item and "TextButton" or "Frame", scroll, {Name = item and item.Id or "EmptySlot", LayoutOrder = index})
			if item then card.Text = "" end
			local stroke = Style.Surface(card, Style.Slot, 4)
			if not item then continue end
			local categoryLabel = label(card, string.upper(item.Kind), UDim2.fromOffset(5, 4), UDim2.fromOffset(78, 12), 9, Style.Muted)
			categoryLabel.TextXAlignment = Enum.TextXAlignment.Center
			local picture = make("Frame", card, {Position = UDim2.fromOffset(3, 14), Size = UDim2.fromOffset(122, 100), BackgroundTransparency = 1})
			make("UIScale", picture, {Scale = 0.68})
			Style.Icon(picture, item)
			local title = label(card, item.Name, UDim2.fromOffset(4, 82), UDim2.fromOffset(82, 15), 10)
			title.TextXAlignment = Enum.TextXAlignment.Center
			local copies = Catalog.Copies(player, item.Kind, item.Name)
			if copies > 1 then
				local stack = label(card, "x" .. copies, UDim2.fromOffset(41, 64), UDim2.fromOffset(44, 19), 14, Style.Text)
				stack.TextXAlignment, stack.ZIndex, stack.TextStrokeTransparency = Enum.TextXAlignment.Right, 4, 0
			end
			local bar = make("Frame", card, {Position = UDim2.fromOffset(4, 97), Size = UDim2.fromOffset(82, 3), BorderSizePixel = 0,
				BackgroundColor3 = Catalog.Rarity(item.Rarity).Color})
			Ui.Round(bar, 2)
			cards[item.Id] = {Stroke = stroke}
			card.Activated:Connect(function()
				if saleBusy or saleRequest then return end
				confirmItem, saleNote.Text = nil, ""
				selected = item updateSelection()
			end)
		end
		updateSelection()
	end
	for index, kind in ipairs({"All", "Gun", "Rope", "Bomb"}) do
		local tab = Style.Button(panel, kind, UDim2.fromOffset(18 + (index - 1) * 132, 86), UDim2.fromOffset(122, 34), Style.ButtonColor)
		tabs[kind] = tab
		tab.Activated:Connect(function()
			if saleBusy or saleRequest then return end
			confirmItem, saleNote.Text = nil, ""
			selectedKind = kind
			for tabKind, button in pairs(tabs) do
				button.TextColor3 = tabKind == selectedKind and Color3.new(1, 1, 1) or Style.Text
				button:FindFirstChildOfClass("UIStroke").Color = tabKind == selectedKind and Style.Accent or Style.Ink
			end
			scroll.CanvasPosition = Vector2.zero
			refresh()
		end)
	end
	tabs.All.TextColor3 = Color3.new(1, 1, 1)
	tabs.All:FindFirstChildOfClass("UIStroke").Color = Style.Accent
	equip.Activated:Connect(function()
		confirmItem = nil
		if selected and Catalog.Owns(player, selected.Kind, selected.Name) then equipRemote:FireServer(selected.Kind, selected.Name) end
		updateSelection()
	end)
	sell.Activated:Connect(function()
		if saleBusy or not selected or selected.Starter or selected.Admin then return end
		if confirmItem ~= selected.Id and not saleRequest then
			confirmItem = selected.Id
			updateSelection()
			return
		end
		local remote = ReplicatedStorage:FindFirstChild("RequestCosmeticSale")
		if not remote then saleNote.Text = "Selling is still loading." return end
		saleRequest = saleRequest or {itemId = selected.Id, id = HttpService:GenerateGUID(false)}
		saleBusy = true
		updateSelection()
		local ok, result = pcall(function() return remote:InvokeServer(saleRequest.itemId, saleRequest.id) end)
		saleBusy, confirmItem = false, nil
		if ok and type(result) == "table" and not result.retry then saleRequest = nil end
		if ok and type(result) == "table" and result.ok then
			saleNote.Text = string.format("Sold 1 / +%d coins", result.price)
		else
			saleNote.Text = ok and type(result) == "table" and result.message or "Sale not confirmed. Click RETRY."
		end
		refresh()
	end)
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then confirmItem = nil updateSelection() end
	end)
	refresh()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "Admin" or key == "CollectionLoaded" then confirmItem = nil refresh()
		elseif key == "GrappleGunColor" or key == "GrappleRopeColor" or key == "BombColor" then updateSelection() end
	end)
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or not panel.Visible then return end
		local bounds = UserInputService.TouchEnabled and panel.Parent.AbsoluteSize or camera.ViewportSize
		if bounds.X < 1 or bounds.Y < 1 then return end
		local marginX = UserInputService.TouchEnabled and 48 or 28
		local marginY = UserInputService.TouchEnabled and 48 or 64
		local availX = math.max(1, bounds.X - marginX)
		local availY = math.max(1, bounds.Y - marginY)
		scale.Scale = math.min(1, availX / 820, availY / 524)
	end)
	return panel
end
return Inventory

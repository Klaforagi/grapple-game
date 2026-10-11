local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage:WaitForChild("Assets"))
local Catalog = require(script.Parent:WaitForChild("ShopCatalog"))

local ROBUX = utf8.char(0xE002)
local CARD = Color3.fromRGB(44, 48, 64)
local INK = Color3.fromRGB(244, 246, 252)
local MUTED = Color3.fromRGB(176, 186, 204)
local BUY = Color3.fromRGB(0, 170, 85)
local OWNED = Color3.fromRGB(90, 96, 112)
local EDGE = Color3.fromRGB(86, 92, 116)

local M = {}

local function make(class, parent, props)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function corner(parent, radius)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
end

local function withCommas(amount)
	local text = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then break end
	end
	return text
end

local function priceText(price)
	return ROBUX .. " " .. tostring(price)
end

local function inkOn(color)
	local bright = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722
	if bright > 0.7 then return Color3.fromRGB(48, 36, 12) end
	return Color3.new(1, 1, 1)
end

local function styleBuy(button, price, owned)
	button:SetAttribute("Owned", owned == true)
	if owned then
		button.Text = "Owned"
		button.BackgroundColor3 = OWNED
		button.AutoButtonColor = false
		button.Active = false
	else
		button.Text = priceText(price)
		button.BackgroundColor3 = BUY
		button.AutoButtonColor = true
		button.Active = true
	end
end

function M.Mount(screen, onClose)
	local player = Players.LocalPlayer
	local window = make("TextButton", screen, {
		Name = "ShopWindow", Text = "", AutoButtonColor = false, Active = true, Modal = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, 520), BackgroundColor3 = Color3.fromRGB(22, 24, 32),
		BorderSizePixel = 0, Visible = false, ZIndex = 21, ClipsDescendants = true,
	})
	corner(window, 16)
	make("UIStroke", window, {Color = Color3.fromRGB(255, 210, 120), Transparency = 0.55, Thickness = 1.5})
	local scale = make("UIScale", window, {Scale = 1})

	make("TextLabel", window, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Shop",
		Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(180, 58),
		Font = Enum.Font.GothamBold, TextSize = 28, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local balance = make("Frame", window, {
		Name = "Balance", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -64, 0, 29),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		BackgroundColor3 = Color3.fromRGB(16, 18, 26), BorderSizePixel = 0,
	})
	corner(balance, 18)
	make("UIPadding", balance, {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12)})
	make("UIListLayout", balance, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	make("ImageLabel", balance, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(22, 22), LayoutOrder = 1,
	})
	local balanceText = make("TextLabel", balance, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "0", LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = INK,
	})
	local function showBalance()
		balanceText.Text = withCommas(player:GetAttribute("Coins") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(showBalance)
	showBalance()
	local close = make("TextButton", window, {
		Name = "Close", Text = "X", AutoButtonColor = true, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, 29),
		Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(50, 54, 70),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = INK,
	})
	corner(close, 10)
	close.Activated:Connect(function()
		if onClose then onClose() end
	end)
	make("Frame", window, {
		Name = "Accent", Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.fromRGB(255, 196, 72), BorderSizePixel = 0,
	})

	local scroll = make("ScrollingFrame", window, {
		Name = "Catalog", Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -60),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(255, 196, 72),
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	})
	make("UIPadding", scroll, {PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 20)})
	make("UIListLayout", scroll, {
		Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local function section(text, order)
		local header = make("TextLabel", scroll, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = text, LayoutOrder = order,
			Size = UDim2.new(1, -32, 0, 26), Font = Enum.Font.GothamBold, TextSize = 18,
			TextColor3 = Color3.fromRGB(255, 214, 130), TextXAlignment = Enum.TextXAlignment.Left,
		})
		return header
	end

	local entries = {}
	local function track(id, button, price)
		entries[#entries + 1] = {id = id, button = button, price = price}
	end
	local function markOwned(id)
		for _, entry in ipairs(entries) do
			if entry.id == id and id > 0 then styleBuy(entry.button, entry.price, true) end
		end
	end

	section("Gamepasses", 1)
	for index, pass in ipairs(Catalog.Passes) do
		local row = make("Frame", scroll, {
			Name = pass.name, LayoutOrder = index + 1, BackgroundColor3 = CARD, BorderSizePixel = 0,
			Size = UDim2.new(1, -32, 0, 124),
		})
		corner(row, 14)
		make("UIStroke", row, {Color = EDGE, Thickness = 1})
		local art = make("Frame", row, {
			Name = "Art", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(100, 100),
			BackgroundColor3 = pass.color, BorderSizePixel = 0, ClipsDescendants = true,
		})
		corner(art, 12)
		local standIn = make("TextLabel", art, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = pass.name, TextWrapped = true,
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextScaled = true,
			TextColor3 = inkOn(pass.color),
		})
		make("UIPadding", standIn, {
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		})
		make("UITextSizeConstraint", standIn, {MinTextSize = 10, MaxTextSize = 26})
		make("ImageLabel", art, {
			Name = "Picture", BackgroundTransparency = 1, BorderSizePixel = 0, Image = pass.image or "",
			Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 2,
		})
		make("TextLabel", row, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = pass.name,
			Position = UDim2.fromOffset(128, 16), Size = UDim2.new(1, -304, 0, 28),
			Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		make("TextLabel", row, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = pass.description, TextWrapped = true,
			Position = UDim2.fromOffset(128, 48), Size = UDim2.new(1, -304, 0, 60),
			Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		})
		local buy = make("TextButton", row, {
			Name = "Buy", AutoButtonColor = true, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(148, 40), BackgroundColor3 = BUY,
			Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
		})
		corner(buy, 10)
		styleBuy(buy, pass.price, false)
		track(pass.id, buy, pass.price)
		buy.Activated:Connect(function()
			if buy:GetAttribute("Owned") or type(pass.id) ~= "number" or pass.id <= 0 then return end
			pcall(function() MarketplaceService:PromptGamePassPurchase(player, pass.id) end)
		end)
	end

	section("Coins", #Catalog.Passes + 2)
	local coinRow = make("Frame", scroll, {
		Name = "CoinPacks", LayoutOrder = #Catalog.Passes + 3, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, -32, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	})
	make("UIGridLayout", coinRow, {
		CellSize = UDim2.fromOffset(148, 176), CellPadding = UDim2.fromOffset(12, 12),
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for index, pack in ipairs(Catalog.Coins) do
		local card = make("Frame", coinRow, {
			Name = tostring(pack.amount), LayoutOrder = index, BackgroundColor3 = CARD, BorderSizePixel = 0,
		})
		corner(card, 14)
		make("UIStroke", card, {Color = EDGE, Thickness = 1})
		make("ImageLabel", card, {
			Name = "Picture", BackgroundTransparency = 1, BorderSizePixel = 0,
			Image = (type(pack.image) == "string" and pack.image ~= "") and pack.image or Assets.Coins,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(64, 64),
		})
		make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = withCommas(pack.amount),
			Position = UDim2.fromOffset(8, 84), Size = UDim2.new(1, -16, 0, 26),
			Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Coins",
			Position = UDim2.fromOffset(8, 108), Size = UDim2.new(1, -16, 0, 16),
			Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local buy = make("TextButton", card, {
			Name = "Buy", AutoButtonColor = true, BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 132), Size = UDim2.new(1, -20, 0, 34),
			BackgroundColor3 = BUY, Font = Enum.Font.GothamBold, TextSize = 16,
			TextColor3 = Color3.new(1, 1, 1), Text = priceText(pack.price),
		})
		corner(buy, 8)
		buy.Activated:Connect(function()
			if type(pack.id) ~= "number" or pack.id <= 0 then return end
			pcall(function() MarketplaceService:PromptProductPurchase(player, pack.id) end)
		end)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, id, purchased)
		if purchased == true then markOwned(id) end
	end)

	local function refresh()
		scroll.CanvasPosition = Vector2.new(0, 0)
		showBalance()
		task.spawn(function()
			for _, entry in ipairs(entries) do
				if entry.id > 0 and not entry.button:GetAttribute("Owned") then
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.id)
					end)
					if ok and owns == true then styleBuy(entry.button, entry.price, true) end
				end
			end
		end)
	end

	return {window = window, scale = scale, refresh = refresh}
end

return M

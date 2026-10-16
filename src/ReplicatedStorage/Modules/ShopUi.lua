local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage:WaitForChild("Assets"))
local Catalog = require(script.Parent:WaitForChild("ShopCatalog"))
local Remotes = require(script.Parent:WaitForChild("GrappleRemotes"))
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local CrispFit = require(script.Parent:WaitForChild("CrispFit"))

local ROBUX = utf8.char(0xE002)
local INK = Style.Text
local MUTED = Style.Muted
local BUY = Style.Action
local OWNED = Style.Disabled or Style.ButtonColor

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

local function styleBuy(button, price, owned, keepActive, buyColor)
	button:SetAttribute("Owned", owned == true)
	if owned then
		button.Text = "Owned"
		button.AutoButtonColor = keepActive == true
		button.Active = keepActive == true
		Style.Recolor(button, OWNED)
	else
		button.Text = priceText(price)
		button.AutoButtonColor = true
		button.Active = true
		Style.Recolor(button, buyColor or BUY)
	end
end

local function strokeText(label)
	label.TextStrokeColor3 = Style.Ink
	label.TextStrokeTransparency = 0.45
	return label
end

function M.Mount(screen, onClose)
	local player = Players.LocalPlayer
	local window = make("TextButton", screen, {
		Name = "ShopWindow", Text = "", AutoButtonColor = false, Active = true, Modal = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, 520), BackgroundColor3 = Style.Panel,
		BorderSizePixel = 0, Visible = false, ZIndex = 21, ClipsDescendants = true,
	})
	Style.Surface(window, Style.Panel, 8)
	local scale = make("UIScale", window, {Scale = 1})
	local header = make("Frame", window, {Name = "Header", Size = UDim2.new(1, 0, 0, 68), ZIndex = 22})
	Style.Surface(header, Style.Header, 8)

	strokeText(make("TextLabel", header, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "SHOP",
		Position = UDim2.fromOffset(22, 15), Size = UDim2.fromOffset(180, 38),
		Font = Enum.Font.GothamBold, TextSize = 26, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23,
	}))
	local balance = make("Frame", header, {
		Name = "Balance", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -58, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		BackgroundColor3 = Style.CoinBackground or Style.Slot, BorderSizePixel = 0, ZIndex = 23,
	})
	Style.Surface(balance, Style.CoinBackground or Style.Slot, 8)
	make("UIPadding", balance, {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12)})
	make("UIListLayout", balance, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local pictures = {}
	local function picture(parent, props)
		local image = make("ImageLabel", parent, props)
		if type(image.Image) == "string" and image.Image ~= "" then pictures[#pictures + 1] = image end
		return image
	end
	picture(balance, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(22, 22), LayoutOrder = 1,
	})
	local balanceText = strokeText(make("TextLabel", balance, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "0", LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Style.CoinText or INK, ZIndex = 24,
	}))
	local function showBalance()
		balanceText.Text = withCommas(player:GetAttribute("Coins") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(showBalance)
	showBalance()
	local close = Style.Button(header, "X", UDim2.new(1, -14, 0, 34), UDim2.fromOffset(36, 36), Style.Danger)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -14, 0, 34)
	close.Name = "Close"
	close.ZIndex = 24
	close.Activated:Connect(function()
		if onClose then onClose() end
	end)

	local scroll = make("ScrollingFrame", window, {
		Name = "Catalog", Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 12,
		ScrollBarImageColor3 = Style.Text, ScrollBarImageTransparency = 0,
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
	})
	make("UIPadding", scroll, {PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 4)})
	local scrollLayout = make("UIListLayout", scroll, {
		Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
	-- A trailing spacer keeps the canvas taller than the window, so the bar never disappears.
	local scrollSpacer = make("Frame", scroll, {
		Name = "ScrollSpacer", BackgroundTransparency = 1, LayoutOrder = 100000,
		Size = UDim2.fromOffset(0, 24),
	})
	-- Its height is already in screen pixels from the scrollbar fit, so do not bake it again.
	scrollSpacer:SetAttribute("CrispIgnore", true)
	local fittingScroll = false
	local function keepScrollBar()
		if fittingScroll then return end
		local view = scroll.AbsoluteWindowSize.Y
		if view < 1 then return end
		local content = scrollLayout.AbsoluteContentSize.Y - scrollSpacer.Size.Y.Offset
		local needed = math.max(24, view - content + 24)
		if math.abs(scrollSpacer.Size.Y.Offset - needed) < 2 then return end
		fittingScroll = true
		scrollSpacer.Size = UDim2.fromOffset(0, needed)
		fittingScroll = false
	end
	scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(keepScrollBar)
	scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(keepScrollBar)

	local function section(text, order)
		local title = strokeText(make("TextLabel", scroll, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = string.upper(text), LayoutOrder = order,
			Size = UDim2.new(1, -32, 0, 26), Font = Enum.Font.GothamBold, TextSize = 18,
			TextColor3 = Style.Accent, TextXAlignment = Enum.TextXAlignment.Left,
		}))
		return title
	end

	local entries = {}
	local function track(id, button, price, name)
		entries[#entries + 1] = {id = id, button = button, price = price, name = name}
	end
	local function markOwned(id)
		for _, entry in ipairs(entries) do
			if entry.id == id and id > 0 then styleBuy(entry.button, entry.price, true) end
		end
	end

	section("Gamepasses", 1)
	for index, pass in ipairs(Catalog.Passes) do
		local cardColor = Style.AlternateCard and index % 2 == 0 and Style.AlternateCard or Style.Slot
		local buyColor = cardColor == Style.AlternateCard and Style.AlternateAction or BUY
		local row = make("Frame", scroll, {
			Name = pass.name, LayoutOrder = index + 1, BackgroundColor3 = cardColor, BorderSizePixel = 0,
			Size = UDim2.new(1, -32, 0, 124),
		})
		Style.Surface(row, cardColor, 6)
		local art = make("Frame", row, {
			Name = "Art", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(100, 100),
			BackgroundColor3 = pass.color, BorderSizePixel = 0, ClipsDescendants = true,
		})
		corner(art, 12)
		make("UIStroke", art, {Color = Style.Ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		-- The name only fills the tile until a picture exists. Art replaces it.
		if type(pass.image) ~= "string" or pass.image == "" then
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
		end
		picture(art, {
			Name = "Picture", BackgroundTransparency = 1, BorderSizePixel = 0, Image = pass.image or "",
			Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 2,
		})
		strokeText(make("TextLabel", row, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = pass.name,
			Position = UDim2.fromOffset(128, 16), Size = UDim2.new(1, -304, 0, 28),
			Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}))
		make("TextLabel", row, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = pass.description, TextWrapped = true,
			Position = UDim2.fromOffset(128, 48), Size = UDim2.new(1, -304, 0, 60),
			Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Style.Text,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextStrokeTransparency = 1,
		})
		local buy = Style.Button(row, "", UDim2.new(1, -164, 0.5, -20), UDim2.fromOffset(148, 40), buyColor)
		buy.Name = "Buy"
		-- Temporary test toggle. Click again to turn the pass off.
		-- To restore Robux prompts, stop calling ToggleTestPass and prompt pass.id instead.
		local attribute = Catalog.TestAttribute(pass.name)
		local function syncPass()
			styleBuy(buy, pass.price, player:GetAttribute(attribute) == true, true, buyColor)
		end
		syncPass()
		track(pass.id, buy, pass.price, pass.name)
		player:GetAttributeChangedSignal(attribute):Connect(syncPass)
		buy.Activated:Connect(function()
			Remotes.ToggleTestPass:FireServer(pass.name)
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
		local cardColor = Style.AlternateCard and index % 2 == 0 and Style.AlternateCard or Style.Slot
		local buyColor = cardColor == Style.AlternateCard and Style.AlternateAction or BUY
		local card = make("Frame", coinRow, {
			Name = tostring(pack.amount), LayoutOrder = index, BackgroundColor3 = cardColor, BorderSizePixel = 0,
		})
		Style.Surface(card, cardColor, 6)
		picture(card, {
			Name = "Picture", BackgroundTransparency = 1, BorderSizePixel = 0,
			Image = (type(pack.image) == "string" and pack.image ~= "") and pack.image or Assets.Coins,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(64, 64),
		})
		strokeText(make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = withCommas(pack.amount),
			Position = UDim2.fromOffset(8, 84), Size = UDim2.new(1, -16, 0, 26),
			Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
		make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Coins",
			Position = UDim2.fromOffset(8, 106), Size = UDim2.new(1, -16, 0, 22),
			Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Style.Text,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1,
		})
		local buy = Style.Button(card, priceText(pack.price), UDim2.fromOffset(10, 132), UDim2.new(1, -20, 0, 34), buyColor)
		buy.Name = "Buy"
		buy.TextSize = 16
		buy.Activated:Connect(function()
			if type(pack.id) ~= "number" or pack.id <= 0 then return end
			pcall(function() MarketplaceService:PromptProductPurchase(player, pack.id) end)
		end)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, id, purchased)
		if purchased == true then markOwned(id) end
	end)

	-- The shop stays hidden until the button is pressed. Fetch the pictures now
	-- so the first open does not pop them in over the tiles.
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync(pictures) end)
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

	local applyFit = CrispFit.attach(window, scale)
	return {window = window, scale = scale, refresh = refresh, applyFit = applyFit}
end

return M

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage:WaitForChild("Assets"))
local Catalog = require(script.Parent:WaitForChild("UpgradeCatalog"))

local WINDOW_X, WINDOW_Y = 640, 584
local ROBUX = utf8.char(0xE002)
local INK = Color3.fromRGB(244, 246, 252)
local MUTED = Color3.fromRGB(176, 186, 204)
local CARD = Color3.fromRGB(44, 48, 64)
local BUY = Color3.fromRGB(0, 170, 85)
local IDLE = Color3.fromRGB(90, 96, 112)
local GOLD = Color3.fromRGB(255, 196, 72)
local EDGE = Color3.fromRGB(86, 92, 116)
local ACCENTS = {
	speed = Color3.fromRGB(255, 196, 72),
	distance = Color3.fromRGB(96, 196, 255),
	duration = Color3.fromRGB(72, 214, 160),
	resistance = Color3.fromRGB(255, 140, 120),
}

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

function M.Mount(screen, onClose)
	local player = Players.LocalPlayer
	local purchaseRemote
	local rows = {}
	local statusText = ""

	local window = make("TextButton", screen, {
		Name = "UpgradeWindow", Text = "", AutoButtonColor = false, Active = true, Modal = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_X, WINDOW_Y), BackgroundColor3 = Color3.fromRGB(22, 24, 32),
		BorderSizePixel = 0, Visible = false, ZIndex = 25, ClipsDescendants = true,
	})
	corner(window, 16)
	make("UIStroke", window, {Color = GOLD, Transparency = 0.45, Thickness = 1.5})
	local scale = make("UIScale", window, {Scale = 1})

	make("TextLabel", window, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Upgrades",
		Position = UDim2.fromOffset(22, 8), Size = UDim2.fromOffset(220, 32),
		Font = Enum.Font.GothamBold, TextSize = 26, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 26,
	})
	make("TextLabel", window, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Spend coins or Robux to strengthen your grapple gun",
		Position = UDim2.fromOffset(22, 38), Size = UDim2.fromOffset(360, 18),
		Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 26,
	})

	local balance = make("Frame", window, {
		Name = "Balance", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -64, 0, 29),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		BackgroundColor3 = Color3.fromRGB(16, 18, 26), BorderSizePixel = 0, ZIndex = 26,
	})
	corner(balance, 18)
	make("UIPadding", balance, {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12)})
	make("UIListLayout", balance, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	make("ImageLabel", balance, {
		BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(22, 22), LayoutOrder = 1, ZIndex = 27,
	})
	local balanceText = make("TextLabel", balance, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "0", LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = INK, ZIndex = 27,
	})
	local close = make("TextButton", window, {
		Name = "Close", Text = "X", AutoButtonColor = true, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, 29),
		Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(50, 54, 70),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = INK, ZIndex = 27,
	})
	corner(close, 10)
	close.Activated:Connect(function()
		if onClose then onClose() end
	end)
	make("Frame", window, {
		Name = "Accent", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 26,
	})
	local status = make("TextLabel", window, {
		Name = "Status", BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		Position = UDim2.fromOffset(22, 70), Size = UDim2.new(1, -44, 0, 18),
		Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Color3.fromRGB(255, 150, 140),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 26,
	})

	local list = make("Frame", window, {
		Name = "Ranks", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 94), Size = UDim2.new(1, -32, 1, -110),
	})
	make("UIListLayout", list, {
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local function paint(row)
		local stat = row.stat
		local rank = Catalog.Rank(player, stat.id)
		local coins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
		local loaded = player:GetAttribute("UpgradesLoaded") == true
		local cost = Catalog.Cost(rank)
		row.rankLabel.Text = string.format("Rank %d / %d", rank, Catalog.MaxRank)
		row.current.Text = Catalog.Text(stat, rank)
		for index, pip in ipairs(row.pips) do
			pip.BackgroundColor3 = index <= rank and ACCENTS[stat.accent] or Color3.fromRGB(22, 24, 32)
		end
		local afford = loaded and cost ~= nil and coins >= cost and not row.pending
		row.button.Active = loaded and cost ~= nil and not row.pending
		row.button.AutoButtonColor = afford
		row.button.BackgroundColor3 = afford and BUY or IDLE
		row.icon.Visible = cost ~= nil and not row.pending
		row.robux.Active = loaded and cost ~= nil and not row.pending
		row.robux.AutoButtonColor = loaded and cost ~= nil and not row.pending
		row.robux.BackgroundColor3 = (loaded and cost ~= nil and not row.pending) and BUY or IDLE
		row.robux.Visible = cost ~= nil or not loaded
		if not loaded then
			row.buttonText.Text = "..."
			row.robuxText.Text = "..."
			row.next.Text = ""
		elseif row.pending then
			row.buttonText.Text = "..."
			row.robuxText.Text = "..."
			row.next.Text = "→  " .. Catalog.Text(stat, rank + 1)
		elseif cost then
			row.buttonText.Text = withCommas(cost)
			row.robuxText.Text = ROBUX .. " " .. tostring(Catalog.RobuxPrice)
			row.next.Text = "→  " .. Catalog.Text(stat, rank + 1)
		else
			row.buttonText.Text = "MAX"
			row.robuxText.Text = "MAX"
			row.next.Text = "Max rank"
			row.button.Active = false
			row.robux.Active = false
			row.robux.Visible = false
		end
	end

	local function refresh()
		balanceText.Text = withCommas(player:GetAttribute("Coins") or 0)
		status.Text = statusText
		for _, row in pairs(rows) do paint(row) end
	end

	for index, stat in ipairs(Catalog.Stats) do
		local card = make("Frame", list, {
			Name = stat.id, LayoutOrder = index, BackgroundColor3 = CARD, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 112), ZIndex = 26,
		})
		corner(card, 14)
		make("UIStroke", card, {Color = EDGE, Thickness = 1})
		local accent = make("Frame", card, {
			BackgroundColor3 = ACCENTS[stat.accent], BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 14), Size = UDim2.fromOffset(4, 84), ZIndex = 27,
		})
		corner(accent, 2)
		local title = make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = stat.name,
			Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -168, 0, 24),
			Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 27,
		})
		local rankLabel = make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "Rank 0 / 10",
			Position = UDim2.fromOffset(250, 54), Size = UDim2.fromOffset(160, 16),
			Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 27,
		})
		make("TextLabel", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = stat.description,
			Position = UDim2.fromOffset(18, 34), Size = UDim2.new(1, -176, 0, 18),
			Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 27,
		})
		local pips = make("Frame", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 58), Size = UDim2.fromOffset(220, 12), ZIndex = 27,
		})
		make("UIListLayout", pips, {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local pipFrames = {}
		for pipIndex = 1, Catalog.MaxRank do
			local pip = make("Frame", pips, {
				LayoutOrder = pipIndex, BorderSizePixel = 0, Size = UDim2.fromOffset(16, 8),
				BackgroundColor3 = Color3.fromRGB(22, 24, 32), ZIndex = 28,
			})
			corner(pip, 3)
			pipFrames[pipIndex] = pip
		end
		local values = make("Frame", card, {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 76), Size = UDim2.new(1, -176, 0, 24), ZIndex = 27,
		})
		make("UIListLayout", values, {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local current = make("TextLabel", values, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", LayoutOrder = 1,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
			Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = INK, ZIndex = 28,
		})
		local nextText = make("TextLabel", values, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
			Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = GOLD, ZIndex = 28,
		})
		local buys = make("Frame", card, {
			Name = "Buys", BackgroundTransparency = 1, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(128, 76), ZIndex = 27,
		})
		make("UIListLayout", buys, {
			FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local button = make("TextButton", buys, {
			Name = "Buy", Text = "", AutoButtonColor = false, BorderSizePixel = 0,
			Size = UDim2.fromOffset(128, 34), BackgroundColor3 = IDLE, LayoutOrder = 1, ZIndex = 27,
		})
		corner(button, 8)
		make("UIListLayout", button, {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local icon = make("ImageLabel", button, {
			BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(16, 16), LayoutOrder = 1, ZIndex = 28,
		})
		local buttonText = make("TextLabel", button, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34),
			Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), ZIndex = 28,
		})
		local robux = make("TextButton", buys, {
			Name = "BuyRobux", Text = "", AutoButtonColor = false, BorderSizePixel = 0,
			Size = UDim2.fromOffset(128, 34), BackgroundColor3 = BUY, LayoutOrder = 2, ZIndex = 27,
		})
		corner(robux, 8)
		local robuxText = make("TextLabel", robux, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = ROBUX .. " " .. tostring(Catalog.RobuxPrice),
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 15,
			TextColor3 = Color3.new(1, 1, 1), ZIndex = 28,
		})
		local row = {
			stat = stat, pips = pipFrames, rankLabel = rankLabel, current = current,
			next = nextText, button = button, buttonText = buttonText, icon = icon,
			robux = robux, robuxText = robuxText, pending = false,
		}
		rows[stat.id] = row
		title.Text = stat.name
		button.Activated:Connect(function()
			if row.pending or player:GetAttribute("UpgradesLoaded") ~= true then return end
			local rank = Catalog.Rank(player, stat.id)
			local cost = Catalog.Cost(rank)
			if not cost then return end
			if (tonumber(player:GetAttribute("Coins")) or 0) < cost then
				statusText = "Not enough coins"
				refresh()
				return
			end
			if not purchaseRemote then return end
			row.pending = true
			statusText = ""
			refresh()
			purchaseRemote:FireServer(stat.id)
		end)
		robux.Activated:Connect(function()
			if row.pending or player:GetAttribute("UpgradesLoaded") ~= true then return end
			if not Catalog.Cost(Catalog.Rank(player, stat.id)) then return end
			if type(Catalog.RobuxProductId) ~= "number" or Catalog.RobuxProductId <= 0 then return end
			if not purchaseRemote then return end
			row.pending = true
			statusText = ""
			refresh()
			purchaseRemote:FireServer(stat.id, "robux")
		end)
	end

	local function watch(attribute)
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	watch("Coins")
	watch("UpgradesLoaded")
	for _, stat in ipairs(Catalog.Stats) do watch(stat.attribute) end
	refresh()

	task.spawn(function()
		purchaseRemote = ReplicatedStorage:WaitForChild("PurchaseUpgrade")
		local resultRemote = ReplicatedStorage:WaitForChild("UpgradeResult")
		resultRemote.OnClientEvent:Connect(function(ok, statId, _, reason)
			local row = rows[statId]
			if row then row.pending = false end
			if reason == "prompt" and type(Catalog.RobuxProductId) == "number" and Catalog.RobuxProductId > 0 then
				pcall(function() MarketplaceService:PromptProductPurchase(player, Catalog.RobuxProductId) end)
			end
			if ok and reason ~= "prompt" then
				statusText = ""
			elseif reason == "coins" then
				statusText = "Not enough coins"
			elseif reason == "save" then
				statusText = "Couldn't save that upgrade. Your coins were refunded."
			else
				statusText = ""
			end
			refresh()
		end)
	end)

	local function fit()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		if viewport.X < 1 or viewport.Y < 1 then return end
		local fitted = math.min((viewport.X - 24) / WINDOW_X, (viewport.Y - 24) / WINDOW_Y)
		if UserInputService.TouchEnabled then fitted *= 0.85 end
		scale.Scale = math.clamp(fitted, 0.4, 1)
	end

	return {window = window, scale = scale, refresh = refresh, fit = fit}
end

return M

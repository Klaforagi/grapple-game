local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Assets = require(storage:WaitForChild("Assets"))
local ShopUi = require(script.Parent:WaitForChild("ShopUi"))
local UpgradeUi = require(script.Parent:WaitForChild("UpgradeUi"))
local AdminUi = require(script.Parent:WaitForChild("AdminUi"))
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local CosmeticHotbar = require(script.Parent:WaitForChild("CosmeticHotbar"))
local Upgrades = require(script.Parent:WaitForChild("UpgradeCatalog"))
local Remotes = require(script.Parent:WaitForChild("GrappleRemotes"))
local Hourly = require(script.Parent:WaitForChild("HourlyRewards"))
local CrispFit = require(script.Parent:WaitForChild("CrispFit"))
local ToolClient = require(script.Parent:WaitForChild("GrappleToolClient"))
local ToolSetup = require(script.Parent:WaitForChild("GrappleToolSetup"))
local M = {}

function M.Init()
	if M.started then return end
	M.started = true
	local RagdollService = require(script.Parent.RagdollService)
	RagdollService.InitClient()
	RagdollService.WatchLocalFalls()
	local player = Players.LocalPlayer
	-- The default reset action can be ignored while the humanoid state machine
	-- is suppressed for a ragdoll. Route it through the server instead.
	local resetEvent = Instance.new("BindableEvent")
	resetEvent.Event:Connect(function()
		Remotes.ResetCharacter:FireServer()
	end)
	task.spawn(function()
		while not pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", resetEvent) do task.wait() end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local function retire(gui)
		if gui.Name ~= Config.toolName and gui.Name ~= "Grapple Gun" then return end
		local function disable(instance)
			if instance:IsA("LocalScript") then instance.Disabled = true end
		end
		if gui:IsA("ScreenGui") then gui.Enabled = false end
		for _, descendant in ipairs(gui:GetDescendants()) do disable(descendant) end
		gui.DescendantAdded:Connect(disable)
	end
	for _, gui in ipairs(playerGui:GetChildren()) do retire(gui) end
	playerGui.ChildAdded:Connect(retire)
	local function make(class, parent, properties)
		local instance = Instance.new(class)
		for key, value in pairs(properties) do instance[key] = value end
		instance.Parent = parent
		return instance
	end
	local screen = make("ScreenGui", playerGui, {
		Name = "GrappleHUD", ResetOnSpawn = false, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local function rounded(frame)
		make("UICorner", frame, {CornerRadius = UDim.new(0, 12)})
	end
	local CLOSE_RED = Color3.fromRGB(195, 76, 87)
	local GO_GREEN = Color3.fromRGB(62, 165, 110)
	local function withCommas(amount)
		local value = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
		while true do
			local formatted, count = string.gsub(value, "^(%d+)(%d%d%d)", "%1,%2")
			value = formatted
			if count == 0 then return value end
		end
	end
	local function label(parent, text, position, size, color)
		local instance = make("TextLabel", parent, {
			Text = text, Position = position, Size = size, BackgroundTransparency = 1,
			TextColor3 = color or Style.Text, TextSize = 15, Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.45,
		})
		return instance
	end
	local function button(parent, text, position, size, callback, color)
		local b = Style.Button(parent, text, position, size, color or Style.ButtonColor)
		b.TextSize = 13
		if callback then b.Activated:Connect(callback) end
		return b
	end
	local currentRope
	local displayLength = 0
	local shorten, lengthen = false, false
	local beingTethered = false
	local function tool()
		local candidate = player.Character and player.Character:FindFirstChild(Config.toolName)
		return candidate and candidate:IsA("Tool") and candidate or nil
	end
	local function reelStep()
		return displayLength * (Config.ropeLengthFraction or 0.05)
	end
	local function change(delta)
		if not currentRope or not currentRope.Parent then return end
		if delta > 0 then delta *= 2 end
		local minimum = currentRope:GetAttribute("PlayerGrapple") and Config.playerMinDragDistance or Config.minRopeLength
		local maximum = Upgrades.ShotDistance(player, currentRope:GetAttribute("WallGrapple") == true)
		displayLength = math.clamp(displayLength + delta, minimum, maximum)
		Remotes.ChangeLength:FireServer(displayLength)
	end
	local function ragdoll()
		RagdollService.NoteRagdollInput()
		Remotes.ToggleRagdoll:FireServer()
	end
	local FlopMotion = require(script.Parent:WaitForChild("FlopMotion"))
	local lastFlop = -math.huge
	local function flop()
		if UIS:GetFocusedTextBox() or not FlopMotion.CanFlop(player.Character)
			or os.clock() - lastFlop < (Config.flopCooldown or 1.8) then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then direction = camera.CFrame.LookVector end
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 0.01 then return end
		lastFlop = os.clock()
		Remotes.Flop:FireServer(direction.Unit)
	end
	UIS.JumpRequest:Connect(function()
		if UIS.TouchEnabled then flop() end
	end)
	local jumpFlop = require(script.Parent:WaitForChild("MobileFlopButton")).new(flop)
	CAS:BindActionAtPriority("GrappleHUD_Flop", function(_, state)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if UIS:GetFocusedTextBox() or not humanoid or not humanoid:GetAttribute("Ragdolled") then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then flop() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
	-- A compact reel replaces the former full-screen grapple panel.
	-- Its normalized position keeps it at 75% across and 95% down on any screen.
	local reelControls = make("Frame", screen, {
		Name = "ReelControls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.75, 0, 0.95, 12),
		Size = UDim2.fromOffset(110, 72), BackgroundTransparency = 1, Active = true, Visible = false,
	})
	-- The invisible touch target covers both buttons and the gap.
	-- Empty taps on this plate must not reach TouchTapInWorld and release a grapple.
	make("TextButton", reelControls, {
		Name = "ReelTouchGuard", Text = "", AutoButtonColor = false, Active = true,
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2,
	})
	local reelScale = make("UIScale", reelControls, {Scale = 1})
	local function styleReelLabel(textLabel)
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextColor3 = Style.Text
		textLabel.TextStrokeColor3 = Style.Ink
		textLabel.TextStrokeTransparency = 0.35
		textLabel.BackgroundTransparency = 1
	end
	local function toggleWallMode()
		if player:GetAttribute("TestPass_WallMode") ~= true then return end
		local equipped = tool()
		if not equipped or beingTethered then return end
		-- The choice is locked from the moment a shot leaves until it misses or drops.
		if equipped:GetAttribute("InUse") == true or equipped:GetAttribute("HasGrappled") == true then return end
		Remotes.ToggleWallMode:FireServer()
	end
	local ropeLength = label(reelControls, "", UDim2.fromOffset(-20, 2), UDim2.fromOffset(150, 18))
	ropeLength.TextSize, ropeLength.TextXAlignment = 11, Enum.TextXAlignment.Center
	ropeLength.ZIndex = 3
	styleReelLabel(ropeLength)
	local shortButton = button(reelControls, "−", UDim2.fromOffset(16, 24), UDim2.fromOffset(34, 36))
	shortButton.Font, shortButton.TextSize, shortButton.ZIndex = Enum.Font.GothamBlack, 22, 3
	local longButton = button(reelControls, "+", UDim2.fromOffset(60, 24), UDim2.fromOffset(34, 36))
	longButton.Font, longButton.TextSize, longButton.ZIndex = Enum.Font.GothamBlack, 22, 3
	if UIS.KeyboardEnabled and not UIS.TouchEnabled then
		for _, hint in ipairs({{"(Q)", -18}, {"(E)", 100}}) do
			local text = label(reelControls, hint[1], UDim2.fromOffset(hint[2], 24), UDim2.fromOffset(28, 36))
			text.TextSize, text.TextXAlignment = 13, Enum.TextXAlignment.Center
			text.ZIndex = 3
			styleReelLabel(text)
		end
	end
	local reelHint = label(reelControls, "Hold to adjust length", UDim2.fromOffset(-20, 63), UDim2.fromOffset(150, 18))
	reelHint.TextSize, reelHint.TextXAlignment = 11, Enum.TextXAlignment.Center
	reelHint.ZIndex = 3
	styleReelLabel(reelHint)
	local wallControls = make("Frame", screen, {
		Name = "WallModeControls", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.94, 0, 0.5, 0),
		Size = UDim2.fromOffset(78, 36), BackgroundTransparency = 1, Visible = false,
	})
	local wallScale = make("UIScale", wallControls, {Scale = 1})
	local wallLabel = label(wallControls, "Wall Mode", UDim2.fromOffset(-36, -22), UDim2.fromOffset(150, 18))
	wallLabel.TextSize, wallLabel.TextXAlignment = 11, Enum.TextXAlignment.Center
	styleReelLabel(wallLabel)
	if UIS.KeyboardEnabled and not UIS.TouchEnabled then wallLabel.Text = "Wall Mode (X)" end
	local wallButton = button(wallControls, "OFF", UDim2.fromOffset(0, 0), UDim2.fromOffset(78, 36), toggleWallMode, Color3.fromRGB(176, 64, 64))
	wallButton.Font, wallButton.TextSize = Enum.Font.GothamBlack, 14
	local inventoryOpen = false
	-- Square buttons with the name underneath, outside the button.
	local STACK_W, BUTTON, CAPTION_H, STRIDE = 112, 44, 16, 70
	local STACK_H = STRIDE * 3 + BUTTON + 2 + CAPTION_H
	local buttonX = math.floor((STACK_W - BUTTON) / 2)
	local leftStack = make("Frame", screen, {
		Name = "LeftStack", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 12, 0.5, -94),
		Size = UDim2.fromOffset(STACK_W, STACK_H), BackgroundTransparency = 1, ZIndex = 3,
	})
	local leftStackScale = make("UIScale", leftStack, {Scale = 1})
	local function stackButton(text, index, image, callback)
		local y = index * STRIDE
		local b = button(leftStack, "", UDim2.fromOffset(buttonX, y), UDim2.fromOffset(BUTTON, BUTTON), callback)
		local icon = make("ImageLabel", b, {
			Name = "Icon", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), ZIndex = 4,
		})
		make("UICorner", icon, {CornerRadius = UDim.new(0, 6)})
		local caption = label(leftStack, text, UDim2.fromOffset(0, y + BUTTON + 1), UDim2.fromOffset(STACK_W, CAPTION_H))
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextYAlignment = Enum.TextYAlignment.Top
		caption.Font = Enum.Font.GothamBlack
		caption.TextSize = 14
		caption.TextTruncate = Enum.TextTruncate.None
		caption.ZIndex = 3
		return b
	end
	local shopButton = stackButton("SHOP", 0, Assets.Shop)
	shopButton.Name = "ShopButton"
	local upgradeButton = stackButton("UPGRADES", 1, Assets.Upgrades)
	upgradeButton.Name = "UpgradeButton"
	local inventoryButton = stackButton("INVENTORY", 2, Assets.Inventory)
	local ragdollButton = stackButton("RAGDOLL", 3, Assets.Ragdoll, ragdoll)
	ragdollButton.Name = "RagdollButton"
	local coins = make("Frame", screen, {
		Name = "Coins", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8),
		Size = UDim2.fromOffset(144, 40),
		BorderSizePixel = 0, ClipsDescendants = false, ZIndex = 2,
	})
	local coinScale = make("UIScale", coins, {Scale = 1})
	Style.Surface(coins, Style.Slot, 6)
	make("UIPadding", coins, {
		PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0),
	})
	make("UIListLayout", coins, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local coinIconSlot = make("Frame", coins, {
		Name = "IconSlot", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(40, 40), LayoutOrder = 1, ZIndex = 3, ClipsDescendants = false,
	})
	make("ImageLabel", coinIconSlot, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(40, 40), ZIndex = 3,
	})
	local coinAmount = label(coins, "0", UDim2.fromOffset(0, 0), UDim2.fromOffset(92, 40))
	coinAmount.Name = "Amount"
	coinAmount.LayoutOrder = 2
	coinAmount.ZIndex = 3
	styleReelLabel(coinAmount)
	coinAmount.TextSize = 20
	coinAmount.TextYAlignment = Enum.TextYAlignment.Center
	-- Width follows the digit count, not the rendered glyph width, so 8 and 1
	-- stay in the same frame until a digit is gained or lost.
	local coinDigits = 0
	local function updateCoins()
		local shown = withCommas(player:GetAttribute("Coins"))
		coinAmount.Text = shown
		local digits = math.max(1, #shown)
		if digits == coinDigits then return end
		coinDigits = digits
		local textWidth = digits * 14 + 4
		coinAmount.Size = UDim2.fromOffset(textWidth, 40)
		coins.Size = UDim2.fromOffset(52 + textWidth, 40)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(updateCoins)
	updateCoins()
	-- The colored rim lives on the inner plate. The button keeps its ink stroke,
	-- so phones still draw a sweep around the edge instead of tinting the square.
	local ragdollBorder = make("UIStroke", ragdollButton:FindFirstChild("Surface"), {
		Name = "ManualRagdollBorder", ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(255, 255, 255), Thickness = 3, Enabled = false,
	})
	local ragdollBorderGradient = make("UIGradient", ragdollBorder, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 140, 180)),
			ColorSequenceKeypoint.new(0.7, Color3.fromRGB(60, 255, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 255, 255)),
		}),
	})
	if UIS.KeyboardEnabled and not UIS.TouchEnabled then
		local hint = label(ragdollButton, "(R)", UDim2.new(1, 6, 0, 0), UDim2.fromOffset(28, 44))
		hint.TextSize, hint.TextXAlignment = 13, Enum.TextXAlignment.Center
		hint.TextYAlignment = Enum.TextYAlignment.Center
		styleReelLabel(hint)
	end
	local inventory = require(script.Parent:WaitForChild("CollectionUi")).CreateInventory(screen, Remotes.SetGrappleColor, function() inventoryOpen = false end)
	local function hold(b, direction)
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if direction < 0 then shorten = true else lengthen = true end
				change(direction * reelStep())
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if direction < 0 then shorten = false else lengthen = false end
			end
		end)
	end
	hold(shortButton, -1)
	hold(longButton, 1)
	local tetherInfo = {incoming = nil, outgoing = nil}
	local escapeNote = ""
	local escapePending = false
	-- Bottom-anchored at the old text's bottom edge, so escape buttons grow upward.
	local tetherPanel = make("Frame", screen, {
		Name = "TetherCountdown", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.75, 28),
		Size = UDim2.fromOffset(380, 56), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
	})
	local tetherScale = make("UIScale", tetherPanel, {Scale = 1})
	local tetherText = label(tetherPanel, "", UDim2.fromOffset(12, 4), UDim2.new(1, -24, 1, -16), Color3.new(1, 1, 1))
	styleReelLabel(tetherText)
	tetherText.TextXAlignment, tetherText.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
	tetherText.Font, tetherText.TextScaled = Enum.Font.GothamBold, true
	make("UITextSizeConstraint", tetherText, {MinTextSize = 10, MaxTextSize = 18})
	local escapeRow = make("Frame", tetherPanel, {
		Name = "Escape", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 1, Visible = false,
	})
	local function requestEscape(method)
		if not beingTethered or escapePending then return end
		if method == "kill" then
			local productId = Config.escapeKillRobuxProductId
			if type(productId) ~= "number" or productId <= 0 then return end
		end
		escapePending = true
		escapeNote = ""
		Remotes.EscapeTether:FireServer(method)
	end
	local coinEscape = button(escapeRow, "", UDim2.fromOffset(0, 0), UDim2.new(0.5, -6, 1, 0), function()
		requestEscape("coins")
	end, GO_GREEN)
	local coinFace = make("Frame", coinEscape, {
		Name = "Face", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Active = false,
	})
	make("UIListLayout", coinFace, {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local coinIcon = make("ImageLabel", coinFace, {
		BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(16, 16), LayoutOrder = 1, ZIndex = 3,
	})
	local coinEscapeText = make("TextLabel", coinFace, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = Style.Text,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.45,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), LayoutOrder = 2, ZIndex = 3,
	})
	local killEscape = button(escapeRow, utf8.char(0xE002) .. "  Kill (" .. tostring(Config.escapeKillRobuxPrice or 19) .. ")", UDim2.new(0.5, 6, 0, 0), UDim2.new(0.5, -6, 1, 0), function()
		requestEscape("kill")
	end, GO_GREEN)
	killEscape.TextSize = 15
	killEscape.TextColor3 = Style.Text
	local function clearIncoming()
		beingTethered = false
		tetherInfo.incoming = nil
		escapePending = false
		escapeNote = ""
	end
	Remotes.HasBeenGrappled.OnClientEvent:Connect(function(attacker, deadline)
		clearIncoming()
		if not attacker or typeof(deadline) ~= "number" then return end
		beingTethered = true
		tetherInfo.incoming = {name = attacker.Name, deadline = deadline}
	end)
	Remotes.EscapeTether.OnClientEvent:Connect(function(ok, reason)
		escapePending = false
		if reason == "prompt" then
			local productId = Config.escapeRobuxProductId
			if type(productId) == "number" and productId > 0 then
				pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
			end
		elseif reason == "killprompt" then
			local productId = Config.escapeKillRobuxProductId
			if type(productId) == "number" and productId > 0 then
				pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
			end
		elseif reason == "coins" then
			escapeNote = "Need " .. tostring(Config.escapeCoinCost or 30)
		elseif ok then
			escapeNote = ""
		end
	end)
	local settingsOpen = false
	local settingsWindow
	local codexOpen = false
	local codexWindow
	local shopOpen = false
	local shopWindow
	local upgradesOpen = false
	local upgradesWindow
	local adminUi
	local function hideAdmin()
		if adminUi then adminUi.hide() end
	end
	-- The custom slots can tint each cosmetic image, including the rope badge.
	-- One owner coordinates hotbar visibility across windows, including the station.
	local function overlayOpen()
		return shopOpen or upgradesOpen or inventoryOpen or codexOpen or player:GetAttribute("CosmeticRollOpen") == true
	end
	local syncCosmeticHotbar = CosmeticHotbar.Mount(screen, player, overlayOpen)
	local function syncHotbar()
		syncCosmeticHotbar()
		local function apply()
			return pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		end
		if apply() then return end
		task.defer(function()
			apply()
		end)
	end
	local function hideShop()
		shopOpen = false
		if shopWindow then shopWindow.Visible = false end
		syncHotbar()
	end
	local function hideUpgrades()
		upgradesOpen = false
		if upgradesWindow then upgradesWindow.Visible = false end
		syncHotbar()
	end
	settingsWindow = make("Frame", screen, {
		Name = "SettingsWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(330, 300), Visible = false,
	})
	Style.Surface(settingsWindow, Style.Panel, 8)
	local settingsHeader = make("Frame", settingsWindow, {Name = "Header", Size = UDim2.new(1, 0, 0, 46)})
	Style.Surface(settingsHeader, Style.Header, 8)
	local settingsScale = make("UIScale", settingsWindow, {Scale = 1})
	local settingsTitle = label(settingsHeader, "SETTINGS", UDim2.fromOffset(16, 8), UDim2.fromOffset(230, 30))
	settingsTitle.TextSize = 20
	local closeSettings = button(settingsHeader, "X", UDim2.fromOffset(284, 6), UDim2.fromOffset(34, 34), nil, CLOSE_RED)
	local function showSettings(visible)
		settingsOpen = visible
		settingsWindow.Visible = visible
		if visible and codexWindow then
			codexOpen = false
			codexWindow.Visible = false
		end
		if visible then
			inventoryOpen = false
			hideShop()
			hideUpgrades()
			hideAdmin()
		end
	end
	closeSettings.Activated:Connect(function() showSettings(false) end)

	-- Sits in the free part of the top bar, immediately right of Roblox's own menu.
	local menuOpen = false
	local menuScreen = make("ScreenGui", playerGui, {
		Name = "GameMenu", ResetOnSpawn = false, DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
	})
	local topPills = make("Frame", menuScreen, {
		Name = "TopPills", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	})
	make("UIPadding", topPills, {PaddingLeft = UDim.new(0, 4)})
	make("UIListLayout", topPills, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local function pill(parent, name, order)
		local instance = make("TextButton", parent, {
			Name = name, Text = "", AutoButtonColor = true, BorderSizePixel = 0,
			BackgroundColor3 = Style.Ink, BackgroundTransparency = 0,
			Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Style.Text,
			TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.45,
			LayoutOrder = order,
		})
		make("UICorner", instance, {CornerRadius = UDim.new(1, 0)})
		make("UIStroke", instance, {Color = Style.Muted, Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		return instance
	end
	local menuButton = pill(topPills, "MenuButton", 1)
	menuButton.Text = "Menu"
	menuButton.AutomaticSize = Enum.AutomaticSize.X
	menuButton.Size = UDim2.fromOffset(0, 32)
	make("UIPadding", menuButton, {PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)})
	local muteButton = pill(topPills, "MuteButton", 2)
	muteButton.Size = UDim2.fromOffset(32, 32)
	make("ImageLabel", muteButton, {
		Name = "Icon", BackgroundTransparency = 1, Image = "rbxassetid://253828517", ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18),
	})
	local muteMark = make("Frame", muteButton, {
		Name = "MuteSlash", BackgroundColor3 = Color3.fromRGB(255, 65, 65), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(24, 3), Rotation = -45, ZIndex = 2, Visible = false,
	})
	local hourlyButton = pill(topPills, "HourlyButton", 3)
	hourlyButton.Size = UDim2.fromOffset(32, 32)
	make("ImageLabel", hourlyButton, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(23, 23),
	})
	local hourlyBadge = make("Frame", hourlyButton, {
		Name = "Alert", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromRGB(195, 76, 87),
		BorderSizePixel = 0, ZIndex = 5, Visible = false, Active = false,
	})
	make("UICorner", hourlyBadge, {CornerRadius = UDim.new(1, 0)})
	local hourlyBang = label(hourlyBadge, "!", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	hourlyBang.TextXAlignment = Enum.TextXAlignment.Center
	hourlyBang.TextYAlignment = Enum.TextYAlignment.Center
	hourlyBang.Font = Enum.Font.GothamBlack
	hourlyBang.TextSize = 12
	hourlyBang.ZIndex = 6
	hourlyBang.Active = false
	local musicMuted = false
	local menuList = make("Frame", screen, {
		Name = "MenuList", Visible = false, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(168, 0), BorderSizePixel = 0, ZIndex = 20,
	})
	Style.Surface(menuList, Style.Panel, 8)
	make("UIPadding", menuList, {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)})
	make("UIListLayout", menuList, {SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center})
	local function styleMenuEntry(entry)
		local hovered, selected = false, false
		make("UICorner", entry, {CornerRadius = UDim.new(0, 8)})
		local function updateHighlight()
			entry.BackgroundColor3 = Style.Header
			entry.BackgroundTransparency = (hovered or selected) and 0.15 or 1
		end
		entry.MouseEnter:Connect(function() hovered = true; updateHighlight() end)
		entry.MouseLeave:Connect(function() hovered = false; updateHighlight() end)
		entry.SelectionGained:Connect(function() selected = true; updateHighlight() end)
		entry.SelectionLost:Connect(function() selected = false; updateHighlight() end)
		menuList:GetPropertyChangedSignal("Visible"):Connect(function()
			if not menuList.Visible then hovered = false; selected = false; updateHighlight() end
		end)
	end
	local adminEntry = make("TextButton", menuList, {
		Name = "Admin", Text = "", AutoButtonColor = false, LayoutOrder = 0, Visible = false,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 44), ZIndex = 21,
	})
	styleMenuEntry(adminEntry)
	local adminMark = label(adminEntry, "A", UDim2.fromOffset(10, 11), UDim2.fromOffset(22, 22))
	adminMark.Font, adminMark.TextSize = Enum.Font.GothamBlack, 16
	adminMark.TextXAlignment = Enum.TextXAlignment.Center
	adminMark.ZIndex = 22
	local adminEntryLabel = label(adminEntry, "Admin", UDim2.fromOffset(40, 0), UDim2.new(1, -48, 1, 0))
	adminEntryLabel.Font, adminEntryLabel.TextSize = Enum.Font.GothamBold, 18
	adminEntryLabel.TextColor3 = Style.Text
	adminEntryLabel.TextYAlignment = Enum.TextYAlignment.Center
	adminEntryLabel.ZIndex = 22
	local function syncAdminEntry()
		local allowed = player:GetAttribute("Admin") == true
		adminEntry.Visible = allowed
		if not allowed then hideAdmin() end
	end
	player:GetAttributeChangedSignal("Admin"):Connect(syncAdminEntry)
	syncAdminEntry()
	local settingsEntry = make("TextButton", menuList, {
		Name = "Settings", Text = "", AutoButtonColor = false, LayoutOrder = 1,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 44), ZIndex = 21,
	})
	styleMenuEntry(settingsEntry)
	make("ImageLabel", settingsEntry, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Settings, ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(22, 22), ZIndex = 22,
	})
	local settingsEntryLabel = label(settingsEntry, "Settings", UDim2.fromOffset(40, 0), UDim2.new(1, -48, 1, 0))
	settingsEntryLabel.Font, settingsEntryLabel.TextSize = Enum.Font.GothamBold, 18
	settingsEntryLabel.TextColor3 = Style.Text
	settingsEntryLabel.TextYAlignment = Enum.TextYAlignment.Center
	settingsEntryLabel.ZIndex = 22
	local codexEntry = make("TextButton", menuList, {
		Name = "Codex", Text = "", AutoButtonColor = false, LayoutOrder = 2,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 44), ZIndex = 21,
	})
	styleMenuEntry(codexEntry)
	make("ImageLabel", codexEntry, {
		Name = "Icon", BackgroundTransparency = 1, Image = Assets.Codex, ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(22, 22), ZIndex = 22,
	})
	local codexEntryLabel = label(codexEntry, "Codex", UDim2.fromOffset(40, 0), UDim2.new(1, -48, 1, 0))
	codexEntryLabel.Font, codexEntryLabel.TextSize = Enum.Font.GothamBold, 18
	codexEntryLabel.TextColor3 = Style.Text
	codexEntryLabel.TextYAlignment = Enum.TextYAlignment.Center
	codexEntryLabel.ZIndex = 22
	codexWindow = make("Frame", screen, {
		Name = "CodexWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 420), Visible = false,
	})
	Style.Surface(codexWindow, Style.Panel, 8)
	local codexHeader = make("Frame", codexWindow, {Name = "Header", Size = UDim2.new(1, 0, 0, 50)})
	Style.Surface(codexHeader, Style.Header, 8)
	local codexScale = make("UIScale", codexWindow, {Scale = 1})
	local codexTitle = label(codexHeader, "CODEX", UDim2.fromOffset(16, 10), UDim2.fromOffset(220, 30))
	codexTitle.TextSize = 20
	local closeCodex = button(codexHeader, "X", UDim2.new(1, -46, 0, 8), UDim2.fromOffset(34, 34), nil, CLOSE_RED)
	require(script.Parent:WaitForChild("CollectionUi")).PopulateCodex(codexWindow)
	local function showCodex(visible)
		codexOpen = visible
		codexWindow.Visible = visible
		if visible then
			inventoryOpen = false
			settingsOpen = false
			settingsWindow.Visible = false
			hideShop()
			hideUpgrades()
			hideAdmin()
		end
		syncHotbar()
	end
	closeCodex.Activated:Connect(function() showCodex(false) end)
	local function placeMenuList()
		local origin = screen.AbsolutePosition
		local pos = menuButton.AbsolutePosition
		local size = menuButton.AbsoluteSize
		menuList.Position = UDim2.fromOffset(pos.X - origin.X, pos.Y + size.Y - origin.Y + 4)
	end
	local showHourly
	local function showMenu(visible)
		menuOpen = visible
		menuList.Visible = visible
		if visible then
			placeMenuList()
			if showHourly then showHourly(false) end
		end
	end
	local function pointerInside(gui, x, y)
		local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
		return x >= pos.X and x <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y
	end
	local hourlyOpen = false
	local hourlyWindow = make("Frame", screen, {
		Name = "HourlyWindow", AnchorPoint = Vector2.new(0, 0), Visible = false,
		Size = UDim2.fromOffset(300, 332), BorderSizePixel = 0, ZIndex = 24,
	})
	Style.Surface(hourlyWindow, Style.Panel, 8)
	local hourlyHeader = make("Frame", hourlyWindow, {Name = "Header", Size = UDim2.new(1, 0, 0, 46), ZIndex = 25})
	Style.Surface(hourlyHeader, Style.Header, 8)
	local hourlyTitle = label(hourlyHeader, "PLAYTIME REWARDS", UDim2.fromOffset(14, 8), UDim2.fromOffset(210, 30))
	hourlyTitle.TextSize = 18
	hourlyTitle.TextStrokeTransparency = 1
	hourlyTitle.ZIndex = 26
	local closeHourly = button(hourlyHeader, "X", UDim2.new(1, -44, 0, 6), UDim2.fromOffset(34, 34), nil, CLOSE_RED)
	closeHourly.ZIndex = 26
	local hourlyPlayed = label(hourlyWindow, "Played today: 0:00", UDim2.fromOffset(14, 54), UDim2.new(1, -28, 0, 20))
	hourlyPlayed.TextSize = 14
	hourlyPlayed.TextStrokeTransparency = 1
	hourlyPlayed.ZIndex = 25
	local hourlyRows = {}
	local function clockText(seconds)
		seconds = math.max(0, math.floor(seconds))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	for index, tier in ipairs(Hourly.Tiers) do
		local y = 82 + (index - 1) * 48
		local row = make("Frame", hourlyWindow, {
			Name = "Tier" .. tier.minutes, Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -24, 0, 42), BorderSizePixel = 0, ZIndex = 25,
		})
		Style.Surface(row, Style.Slot, 6)
		local timeLabel = label(row, tier.minutes .. " MIN", UDim2.fromOffset(8, 4), UDim2.fromOffset(72, 34))
		timeLabel.TextSize = 14
		timeLabel.TextStrokeTransparency = 1
		timeLabel.TextTruncate = Enum.TextTruncate.None
		timeLabel.ZIndex = 26
		local coinIcon = make("ImageLabel", row, {
			BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 84, 0.5, 0),
			Size = UDim2.fromOffset(16, 16), ZIndex = 26,
		})
		local coinLabel = label(row, "+" .. tier.coins, UDim2.fromOffset(106, 4), UDim2.fromOffset(44, 34))
		coinLabel.TextSize = 14
		coinLabel.TextColor3 = Style.Accent
		coinLabel.TextStrokeTransparency = 1
		coinLabel.TextTruncate = Enum.TextTruncate.None
		coinLabel.ZIndex = 26
		local stateLabel = label(row, "", UDim2.new(1, -78, 0, 4), UDim2.fromOffset(66, 34))
		stateLabel.TextSize = 13
		stateLabel.TextXAlignment = Enum.TextXAlignment.Right
		stateLabel.TextStrokeTransparency = 1
		stateLabel.ZIndex = 26
		local claim = button(row, "CLAIM", UDim2.new(1, -74, 0.5, 0), UDim2.fromOffset(64, 26), nil, Color3.fromRGB(62, 165, 110))
		claim.AnchorPoint = Vector2.new(0, 0.5)
		claim.TextSize = 12
		claim.Visible = false
		claim.ZIndex = 27
		claim.Activated:Connect(function()
			Remotes.ClaimHourly:FireServer(index)
		end)
		hourlyRows[index] = {Row = row, Time = timeLabel, Amount = coinLabel, Icon = coinIcon, State = stateLabel, Claim = claim}
	end
	local function fitHourly()
		local phone = UIS.TouchEnabled
		local headerH = phone and 30 or 46
		local rowH = phone and 28 or 42
		local stride = phone and 32 or 48
		local playedGap = phone and 4 or 8
		local playedH = phone and 16 or 20
		local top = headerH + playedGap + playedH + (phone and 6 or 8)
		local text = phone and 13 or 14
		local windowW = phone and 188 or 300
		local iconX = phone and 58 or 84
		local iconSize = phone and 14 or 16
		hourlyWindow.Size = UDim2.fromOffset(windowW, top + #Hourly.Tiers * stride + (phone and 6 or 10))
		hourlyHeader.Size = UDim2.new(1, 0, 0, headerH)
		hourlyTitle.TextSize = phone and 13 or 18
		hourlyTitle.Position = UDim2.fromOffset(phone and 8 or 14, phone and 4 or 8)
		hourlyTitle.Size = UDim2.fromOffset(phone and 148 or 220, phone and 22 or 30)
		closeHourly.Size = UDim2.fromOffset(phone and 22 or 34, phone and 22 or 34)
		closeHourly.Position = UDim2.new(1, phone and -26 or -44, 0, phone and 4 or 6)
		closeHourly.TextSize = phone and 11 or 13
		hourlyPlayed.TextSize = text
		hourlyPlayed.Position = UDim2.fromOffset(phone and 8 or 14, headerH + playedGap)
		hourlyPlayed.Size = UDim2.new(1, phone and -16 or -28, 0, playedH)
		for index, row in ipairs(hourlyRows) do
			local y = top + (index - 1) * stride
			row.Row.Position = UDim2.fromOffset(phone and 6 or 12, y)
			row.Row.Size = UDim2.new(1, phone and -12 or -24, 0, rowH)
			row.Time.TextSize = text
			row.Time.Size = UDim2.fromOffset(phone and 52 or 72, rowH - 6)
			row.Time.Position = UDim2.fromOffset(phone and 6 or 8, 3)
			row.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
			row.Icon.Position = UDim2.new(0, iconX, 0.5, 0)
			row.Amount.TextSize = text
			row.Amount.Position = UDim2.fromOffset(iconX + iconSize + (phone and 4 or 6), 3)
			row.Amount.Size = UDim2.fromOffset(phone and 36 or 44, rowH - 6)
			row.State.TextSize = phone and 12 or 13
			row.State.Position = UDim2.new(1, phone and -62 or -78, 0, 3)
			row.State.Size = UDim2.fromOffset(phone and 54 or 66, rowH - 6)
			row.Claim.Size = UDim2.fromOffset(phone and 52 or 64, phone and 20 or 26)
			row.Claim.Position = UDim2.new(1, phone and -56 or -74, 0.5, 0)
			row.Claim.TextSize = phone and 11 or 12
		end
	end
	fitHourly()
	local function refreshHourly()
		local seconds = player:GetAttribute("HourlySeconds")
		local claimed = player:GetAttribute("HourlyClaimed")
		if type(seconds) ~= "number" then seconds = 0 end
		if type(claimed) ~= "number" then claimed = 0 end
		seconds = math.clamp(seconds, 0, Hourly.Cap())
		hourlyPlayed.Text = "Played today: " .. clockText(seconds)
		local waiting = false
		for index, tier in ipairs(Hourly.Tiers) do
			local row = hourlyRows[index]
			local need = tier.minutes * 60
			local ready = seconds >= need and not Hourly.Has(claimed, index)
			if ready then waiting = true end
			row.Claim.Visible = ready
			row.State.Visible = not ready
			if Hourly.Has(claimed, index) then
				row.State.Text = "Claimed"
				row.State.TextColor3 = Style.Accent
			else
				row.State.Text = clockText(need - seconds)
				row.State.TextColor3 = Style.Muted
			end
		end
		hourlyBadge.Visible = waiting
	end
	local function placeHourly()
		local origin = screen.AbsolutePosition
		local pos = hourlyButton.AbsolutePosition
		local size = hourlyButton.AbsoluteSize
		hourlyWindow.Position = UDim2.fromOffset(pos.X - origin.X, pos.Y + size.Y - origin.Y + 6)
	end
	showHourly = function(visible)
		hourlyOpen = visible
		hourlyWindow.Visible = visible
		if not visible then return end
		showMenu(false)
		fitHourly()
		refreshHourly()
		placeHourly()
	end
	closeHourly.Activated:Connect(function() showHourly(false) end)
	hourlyButton.Activated:Connect(function() showHourly(not hourlyOpen) end)
	player:GetAttributeChangedSignal("HourlySeconds"):Connect(refreshHourly)
	player:GetAttributeChangedSignal("HourlyClaimed"):Connect(refreshHourly)
	refreshHourly()
	menuButton.Activated:Connect(function() showMenu(not menuOpen) end)
	settingsEntry.Activated:Connect(function()
		showMenu(false)
		showSettings(true)
	end)
	codexEntry.Activated:Connect(function()
		showMenu(false)
		showCodex(true)
	end)
	adminUi = AdminUi.Mount(screen, function()
		inventoryOpen = false
		settingsOpen = false
		settingsWindow.Visible = false
		codexOpen = false
		if codexWindow then codexWindow.Visible = false end
		hideShop()
		hideUpgrades()
		showMenu(false)
	end)
	adminEntry.Activated:Connect(function()
		if player:GetAttribute("Admin") ~= true then return end
		showMenu(false)
		adminUi.show(not adminUi.window.Visible)
	end)
	UIS.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if menuOpen then
			if pointerInside(menuButton, input.Position.X, input.Position.Y) then return end
			if pointerInside(menuList, input.Position.X, input.Position.Y) then return end
			showMenu(false)
		end
		if hourlyOpen then
			if pointerInside(hourlyButton, input.Position.X, input.Position.Y) then return end
			if pointerInside(hourlyWindow, input.Position.X, input.Position.Y) then return end
			showHourly(false)
		end
	end)
	GuiService.MenuOpened:Connect(function()
		showMenu(false)
		showHourly(false)
	end)

	local showShop
	local shopUi = ShopUi.Mount(screen, function()
		showShop(false)
	end)
	shopWindow = shopUi.window
	local function fitWindow(apply, windowW, windowH)
		if not apply then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local bounds = UIS.TouchEnabled and screen.AbsoluteSize or camera.ViewportSize
		if bounds.X < 1 or bounds.Y < 1 then return end
		local margin = UIS.TouchEnabled and 48 or 24
		local availX = math.max(1, bounds.X - margin)
		local availY = math.max(1, bounds.Y - margin)
		apply(math.min(1, availX / windowW, availY / windowH))
	end
	local function fitShop()
		fitWindow(shopUi.applyFit, 680, 520)
	end
	local applyLeft = CrispFit.attach(leftStack, leftStackScale)
	local applyCoins = CrispFit.attach(coins, coinScale)
	local applyReel = CrispFit.attach(reelControls, reelScale)
	local applyWall = CrispFit.attach(wallControls, wallScale)
	local applyTether = CrispFit.attach(tetherPanel, tetherScale)
	local applySettings = CrispFit.attach(settingsWindow, settingsScale)
	local applyCodex = CrispFit.attach(codexWindow, codexScale)
	local function fitLeftStack()
		coins.Position = UDim2.new(0, 8, 1, -8)
		local camera = workspace.CurrentCamera
		if not camera then return end
		if not UIS.TouchEnabled then
			applyLeft(1)
			applyCoins(1)
			leftStack.Position = UDim2.new(0, 12, 0.5, -94)
			return
		end
		-- Phones keep the same squares and coin chip, drawn at real pixel sizes.
		local scale = 0.6
		applyLeft(scale)
		applyCoins(scale)
		local viewport = camera.ViewportSize
		local topMargin, bottomMargin = 8, 72
		local height = STACK_H * scale
		local available = math.max(120, viewport.Y - topMargin - bottomMargin)
		local top = topMargin + math.max(0, (available - height) / 2)
		leftStack.Position = UDim2.fromOffset(8, top)
	end
	showShop = function(visible)
		shopOpen = visible
		if visible then
			fitShop()
			hideUpgrades()
			hideAdmin()
		end
		if shopWindow then shopWindow.Visible = visible end
		syncHotbar()
		if not visible then return end
		inventoryOpen = false
		inventory.Visible = false
		settingsOpen = false
		settingsWindow.Visible = false
		codexOpen = false
		if codexWindow then codexWindow.Visible = false end
		showMenu(false)
		shopUi.refresh()
	end
	shopButton.Activated:Connect(function()
		showShop(not shopOpen)
	end)
	local showUpgrades
	local upgradeUi = UpgradeUi.Mount(screen, function()
		showUpgrades(false)
	end)
	upgradesWindow = upgradeUi.window
	showUpgrades = function(visible)
		upgradesOpen = visible
		if visible then
			upgradeUi.fit()
			hideShop()
			hideAdmin()
		end
		if upgradesWindow then upgradesWindow.Visible = visible end
		syncHotbar()
		if not visible then return end
		inventoryOpen = false
		inventory.Visible = false
		settingsOpen = false
		settingsWindow.Visible = false
		codexOpen = false
		if codexWindow then codexWindow.Visible = false end
		showMenu(false)
		upgradeUi.refresh()
	end
	upgradeButton.Activated:Connect(function()
		showUpgrades(not upgradesOpen)
	end)
	inventoryButton.Activated:Connect(function()
		-- Toggle and close competing windows together; separate Activated handlers
		-- must not depend on which callback Roblox dispatches first.
		inventoryOpen = not inventoryOpen
		if inventoryOpen then
			hideShop()
			hideUpgrades()
			hideAdmin()
			showSettings(false)
			showCodex(false)
			showMenu(false)
		end
		inventory.Visible = player.Character ~= nil and inventoryOpen
		syncHotbar()
	end)
	inventory:GetPropertyChangedSignal("Visible"):Connect(syncHotbar)
	local function stationVisibility()
		if player:GetAttribute("CosmeticRollOpen") == true then
			inventoryOpen = false
			inventory.Visible = false
			showSettings(false)
			showCodex(false)
			showMenu(false)
			hideShop()
			hideUpgrades()
			hideAdmin()
		end
		syncHotbar()
	end
	player:GetAttributeChangedSignal("CosmeticRollOpen"):Connect(stationVisibility)
	stationVisibility()

	local settingRevision = {}
	local function saveSetting(key, value, immediate)
		settingRevision[key] = (settingRevision[key] or 0) + 1
		local revision = settingRevision[key]
		local function send()
			if settingRevision[key] == revision then Remotes.SetPlayerSetting:FireServer(key, value) end
		end
		if immediate then send() else task.delay(0.15, send) end
	end

	-- These Lighting changes are client-local, so every player can keep their
	-- own time and shadow preference without changing the server's world.
	local timeControls = make("Frame", settingsWindow, {
		Name = "LocalTimeControls", Position = UDim2.fromOffset(18, 52),
		Size = UDim2.fromOffset(294, 56), BackgroundTransparency = 1,
	})
	local timeLabel = label(timeControls, "Time of Day", UDim2.fromOffset(0, 0), UDim2.fromOffset(294, 16))
	timeLabel.TextXAlignment, timeLabel.Font = Enum.TextXAlignment.Center, Enum.Font.GothamBold
	local timeButtons = {}
	local function applyLocalTime(clock, shouldSave)
		Lighting.ClockTime = clock
		for _, entry in ipairs(timeButtons) do
			Style.Recolor(entry.button, math.abs(entry.clock - clock) < 0.02 and GO_GREEN or Style.ButtonColor)
		end
		if shouldSave then saveSetting("LocalClockTime", clock, true) end
	end
	local presetWidth, presetGap = 140, 14
	for index, preset in ipairs({
		{text = "Day", clock = 8},
		{text = "Night", clock = 20},
	}) do
		local choice = button(timeControls, preset.text, UDim2.fromOffset((index - 1) * (presetWidth + presetGap), 20), UDim2.fromOffset(presetWidth, 36), function()
			applyLocalTime(preset.clock, true)
		end)
		choice.Name = "Time" .. string.gsub(preset.text, ":", "")
		timeButtons[index] = {button = choice, clock = preset.clock}
	end

	local shadowsLabel = label(settingsWindow, "Shadows", UDim2.fromOffset(20, 118), UDim2.fromOffset(220, 32))
	shadowsLabel.Font = Enum.Font.GothamBold
	local shadowsEnabled = Lighting.GlobalShadows
	local shadowsCheckbox = button(settingsWindow, "", UDim2.fromOffset(274, 118), UDim2.fromOffset(32, 32), nil, Style.Slot)
	local function applyShadows(enabled)
		shadowsEnabled = enabled
		Lighting.GlobalShadows = enabled
		shadowsCheckbox.Text = enabled and "X" or ""
		Style.Recolor(shadowsCheckbox, enabled and GO_GREEN or Style.Slot)
	end
	shadowsCheckbox.Activated:Connect(function()
		applyShadows(not shadowsEnabled)
		saveSetting("ShadowsEnabled", shadowsEnabled, true)
	end)

	local musicControls = make("Frame", settingsWindow, {
		Name = "MusicVolumeControls", Position = UDim2.fromOffset(18, 164),
		Size = UDim2.fromOffset(294, 54), BackgroundTransparency = 1,
	})
	local musicLabel = label(musicControls, "Music Volume", UDim2.fromOffset(0, 0), UDim2.fromOffset(294, 18))
	musicLabel.TextXAlignment, musicLabel.Font = Enum.TextXAlignment.Center, Enum.Font.GothamBold
	local musicTrack = make("TextButton", musicControls, {Position = UDim2.fromOffset(7, 32), Size = UDim2.fromOffset(280, 10), BackgroundColor3 = Style.Slot, BorderSizePixel = 0, Text = ""})
	rounded(musicTrack)
	make("UIStroke", musicTrack, {Color = Style.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	local musicKnob = make("Frame", musicTrack, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Style.Accent, BorderSizePixel = 0, ZIndex = 2})
	rounded(musicKnob)
	local adjustingMusic = false
	local musicVolume = 1
	local MusicVolume = require(script.Parent:WaitForChild("MusicVolume"))
	local function applyMuted(muted, shouldSave)
		musicMuted = muted == true
		muteButton:SetAttribute("Muted", musicMuted)
		muteMark.Visible = musicMuted
		MusicVolume.SetMuted(musicMuted)
		if shouldSave then saveSetting("MusicMuted", musicMuted, true) end
	end
	muteButton.Activated:Connect(function()
		applyMuted(not musicMuted, true)
	end)
	local function applyMusicVolume(value)
		musicVolume = math.clamp(value, 0, 1)
		musicKnob.Position = UDim2.fromScale(musicVolume, 0.5)
		musicLabel.Text = string.format("Music Volume  %d%%", math.floor(musicVolume * 100 + 0.5))
		MusicVolume.SetVolume(musicVolume)
	end
	local function setMusicFromPosition(position, shouldSave)
		local fraction = math.clamp((position.X - musicTrack.AbsolutePosition.X) / math.max(1, musicTrack.AbsoluteSize.X), 0, 1)
		applyMusicVolume(fraction)
		if shouldSave then saveSetting("MusicVolume", musicVolume) end
	end
	musicTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then adjustingMusic = true setMusicFromPosition(input.Position, true) end
	end)

	local effectsControls = make("Frame", settingsWindow, {
		Name = "EffectsVolumeControls", Position = UDim2.fromOffset(18, 226),
		Size = UDim2.fromOffset(294, 54), BackgroundTransparency = 1,
	})
	local effectsLabel = label(effectsControls, "Sound Effects", UDim2.fromOffset(0, 0), UDim2.fromOffset(294, 18))
	effectsLabel.TextXAlignment, effectsLabel.Font = Enum.TextXAlignment.Center, Enum.Font.GothamBold
	local effectsTrack = make("TextButton", effectsControls, {Position = UDim2.fromOffset(7, 32), Size = UDim2.fromOffset(280, 10), BackgroundColor3 = Style.Slot, BorderSizePixel = 0, Text = ""})
	rounded(effectsTrack)
	make("UIStroke", effectsTrack, {Color = Style.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	local effectsKnob = make("Frame", effectsTrack, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Style.Accent, BorderSizePixel = 0, ZIndex = 2})
	rounded(effectsKnob)
	local adjustingEffects = false
	local effectsVolume = 1
	local EffectsVolume = require(script.Parent:WaitForChild("EffectsVolume"))
	local function applyEffectsVolume(value)
		effectsVolume = math.clamp(value, 0, 1)
		effectsKnob.Position = UDim2.fromScale(effectsVolume, 0.5)
		effectsLabel.Text = string.format("Sound Effects  %d%%", math.floor(effectsVolume * 100 + 0.5))
		EffectsVolume.SetVolume(effectsVolume)
	end
	local function setEffectsFromPosition(position, shouldSave)
		local fraction = math.clamp((position.X - effectsTrack.AbsolutePosition.X) / math.max(1, effectsTrack.AbsoluteSize.X), 0, 1)
		applyEffectsVolume(fraction)
		if shouldSave then saveSetting("EffectsVolume", effectsVolume) end
	end
	effectsTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then adjustingEffects = true setEffectsFromPosition(input.Position, true) end
	end)
	UIS.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if adjustingMusic then setMusicFromPosition(input.Position, true) end
		if adjustingEffects then setEffectsFromPosition(input.Position, true) end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if adjustingMusic then saveSetting("MusicVolume", musicVolume, true) end
			if adjustingEffects then saveSetting("EffectsVolume", effectsVolume, true) end
			adjustingMusic, adjustingEffects = false, false
		end
	end)

	local function applySavedSettings()
		local savedTime = player:GetAttribute("LocalClockTime")
		local savedShadows = player:GetAttribute("ShadowsEnabled")
		local savedMusic = player:GetAttribute("MusicVolume")
		local savedEffects = player:GetAttribute("EffectsVolume")
		if typeof(savedTime) == "number" then
			Lighting.ClockTime = math.clamp(savedTime, 0, 24)
		end
		for _, entry in ipairs(timeButtons) do
			Style.Recolor(entry.button, math.abs(entry.clock - Lighting.ClockTime) < 0.02 and GO_GREEN or Style.ButtonColor)
		end
		if typeof(savedShadows) ~= "boolean" then savedShadows = Lighting.GlobalShadows end
		applyShadows(savedShadows)
		applyMusicVolume(typeof(savedMusic) == "number" and savedMusic or 1)
		applyMuted(player:GetAttribute("MusicMuted") == true)
		applyEffectsVolume(typeof(savedEffects) == "number" and savedEffects or 1)
	end
	for _, key in ipairs({"LocalClockTime", "ShadowsEnabled", "MusicVolume", "MusicMuted", "EffectsVolume"}) do
		player:GetAttributeChangedSignal(key):Connect(applySavedSettings)
	end
	applySavedSettings()
	local function grapple(target, rope, deadline, username)
		tetherInfo.outgoing = target and typeof(deadline) == "number" and {name = username or target.Name, deadline = deadline} or nil
		currentRope = rope
		displayLength = rope and rope.Length or 0
		shorten, lengthen = false, false
	end
	Remotes.GrappledPlayer.OnClientEvent:Connect(grapple)
	Remotes.GrappledWall.OnClientEvent:Connect(function(attachment, rope)
		-- The wall event's third argument is a Beam, not a countdown deadline.
		grapple(attachment, rope)
	end)
	CAS:BindActionAtPriority("GrappleHUD_TargetMode", function(_, state)
		if UIS:GetFocusedTextBox() or not tool() or beingTethered then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then toggleWallMode() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 2, Config.toggleWallMode)
	UIS.InputBegan:Connect(function(input, processed)
		if processed or UIS:GetFocusedTextBox() then return end
		if input.KeyCode == Config.ragdollKeybind then ragdoll()
		elseif input.KeyCode == Config.shortenRope then shorten = true change(-reelStep())
		elseif input.KeyCode == Config.lengthenRope then lengthen = true change(reelStep()) end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.KeyCode == Config.shortenRope then shorten = false end
		if input.KeyCode == Config.lengthenRope then lengthen = false end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then shorten, lengthen = false, false end
	end)
	UIS.WindowFocusReleased:Connect(function() shorten, lengthen = false, false end)
	local function watchTool(instance)
		if instance:IsA("Tool") and instance.Name == Config.toolName then
			ToolSetup.Prepare(instance, false)
			ToolClient.Init(instance)
		end
	end
	local backpackConnection
	local function watchBackpack(backpack)
		if backpackConnection then backpackConnection:Disconnect() end
		backpackConnection = backpack.ChildAdded:Connect(watchTool)
		for _, instance in ipairs(backpack:GetChildren()) do watchTool(instance) end
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchBackpack(child) end
	end)
	watchBackpack(player:WaitForChild("Backpack"))
	local characterConnection
	local function characterAdded(character)
		clearIncoming()
		grapple()
		if characterConnection then characterConnection:Disconnect() end
		for _, instance in ipairs(character:GetChildren()) do watchTool(instance) end
		characterConnection = character.ChildAdded:Connect(watchTool)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid:GetAttributeChangedSignal("GrappledBy"):Connect(function()
			if humanoid:GetAttribute("GrappledBy") == nil then clearIncoming() end
		end)
		humanoid.Died:Once(function() clearIncoming() grapple() end)
	end
	player.CharacterAdded:Connect(characterAdded)
	player.CharacterRemoving:Connect(function() clearIncoming() grapple() end)
	if player.Character then task.spawn(characterAdded, player.Character) end
	local accumulator, uiAccumulator = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local lines = {}
		for _, side in ipairs({"incoming", "outgoing"}) do
			local info = tetherInfo[side]
			if info then
				local seconds = math.max(0, math.ceil(info.deadline - workspace:GetServerTimeNow()))
				local line = side == "incoming"
					and string.format("Tethered by %s for %d seconds", info.name, seconds)
					or string.format("Tethering %s for %d seconds", info.name, seconds)
				table.insert(lines, line)
			end
		end
		local showEscape = tetherInfo.incoming ~= nil
		local baseHeight = #lines > 1 and 80 or 56
		-- Keep outgoing tether text at the same height as incoming text. The
		-- reserved row is invisible unless this player can actually escape.
		local escapeExtra = #lines > 0 and 44 or 0
		tetherPanel.Visible = #lines > 0
		tetherPanel.Size = UDim2.fromOffset(380, baseHeight + escapeExtra)
		-- On a phone the reserved row keeps the status clear of the hotbar.
		local lift = (escapeExtra > 0 and UIS.TouchEnabled) and escapeExtra or 0
		tetherPanel.Position = UDim2.new(0.5, 0, 0.75, 28 - lift)
		tetherText.Position = UDim2.fromOffset(12, 4)
		tetherText.Size = UDim2.new(1, -24, 0, baseHeight - 8)
		tetherText.Text = table.concat(lines, "\n")
		escapeRow.Visible = showEscape
		local freeEscapes = math.max(0, math.floor(tonumber(player:GetAttribute("FreeEscapes")) or 0))
		coinIcon.Visible = freeEscapes <= 0
		coinEscapeText.Text = escapeNote ~= "" and escapeNote or (freeEscapes > 0 and ("Escape (" .. tostring(freeEscapes) .. " free left)") or ("Escape (" .. tostring(Config.escapeCoinCost or 30) .. ")"))
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if UIS.TouchEnabled then
			local touchGui = playerGui:FindFirstChild("TouchGui")
			local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
			local ragdolled = humanoid and humanoid.Health > 0 and humanoid:GetAttribute("Ragdolled")
				and not humanoid:GetAttribute("CapsuleLocked")
			jumpFlop:Update(jump, ragdolled)
		else
			jumpFlop:Destroy()
		end
		local ragdollActive = humanoid ~= nil and humanoid.Health > 0
			and humanoid:GetAttribute("Ragdolled") == true
			and humanoid:GetAttribute("ManualRagdoll") == true
			and not humanoid:GetAttribute("CapsuleLocked")
		ragdollBorder.Enabled = ragdollActive
		if ragdollActive then
			ragdollBorderGradient.Rotation = (ragdollBorderGradient.Rotation + dt * 150) % 360
		end
		accumulator += dt
		local reelInterval = Config.ropeReelInterval or 1 / 15
		if accumulator >= reelInterval then
			accumulator %= reelInterval
			if shorten ~= lengthen then change((shorten and -1 or 1) * reelStep()) end
		end
		uiAccumulator += dt
		if uiAccumulator < 0.1 then return end
		uiAccumulator = 0
		local camera = workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			local scale = math.clamp(math.min(viewport.X / 800, viewport.Y / 450), 0.7, 1.2)
			applyReel(scale)
			applyWall(scale)
			applyTether(math.clamp(math.min(viewport.X / 480, viewport.Y / 800), 0.55, 1))
			local settingsUiScale = math.clamp(math.min(viewport.X / 800, viewport.Y / 600), 0.7, 1)
			applySettings(settingsUiScale)
			applyCodex(settingsUiScale)
			fitHourly()
			fitShop()
			fitLeftStack()
			upgradeUi.fit()
			if adminUi then adminUi.fit() end
		end
		if menuOpen then placeMenuList() end
		if hourlyOpen then placeHourly() end
		if currentRope and not currentRope.Parent then grapple() end
		local equipped = tool()
		reelControls.Visible = currentRope ~= nil and equipped ~= nil
		wallControls.Visible = equipped ~= nil and player:GetAttribute("TestPass_WallMode") == true
		inventoryButton.Visible = player.Character ~= nil
		ragdollButton.Visible = player.Character ~= nil
		inventory.Visible = player.Character ~= nil and inventoryOpen
		local wallMode = equipped and equipped:GetAttribute("WallMode") == true
		wallButton.Text = wallMode and "ON" or "OFF"
		Style.Recolor(wallButton, wallMode and GO_GREEN or Color3.fromRGB(176, 64, 64))
		if currentRope and not shorten and not lengthen then displayLength = currentRope.Length end
		ropeLength.Text = currentRope and string.format("%.1f studs", displayLength) or ""
	end)
end
return M

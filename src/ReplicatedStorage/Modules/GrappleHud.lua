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
local Upgrades = require(script.Parent:WaitForChild("UpgradeCatalog"))
local Remotes = require(script.Parent:WaitForChild("GrappleRemotes"))
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
	local function label(parent, text, position, size, color)
		local instance = make("TextLabel", parent, {
			Text = text, Position = position, Size = size, BackgroundTransparency = 1,
			TextColor3 = color or Color3.fromRGB(232, 240, 247), TextSize = 15, Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		return instance
	end
	local function button(parent, text, position, size, callback)
		local b = make("TextButton", parent, {
			Text = text, Position = position, Size = size, BackgroundColor3 = Color3.fromRGB(39, 51, 65),
			TextColor3 = Color3.fromRGB(234, 244, 250), TextSize = 13, Font = Enum.Font.GothamMedium, AutoButtonColor = true,
		})
		rounded(b)
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
		Name = "ReelControls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.75, 0, 0.95, 0),
		Size = UDim2.fromOffset(78, 36), BackgroundTransparency = 1, Visible = false,
	})
	local reelScale = make("UIScale", reelControls, {Scale = 1})
	local function styleReelLabel(textLabel)
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextColor3 = Color3.fromRGB(27, 42, 53)
		textLabel.BackgroundTransparency = 1
		make("UIStroke", textLabel, {Color = Color3.fromRGB(255, 255, 255), Thickness = 2})
	end
	local function toggleWallMode()
		local equipped = tool()
		if not equipped or beingTethered then return end
		-- The choice is locked from the moment a shot leaves until it misses or drops.
		if equipped:GetAttribute("InUse") == true or equipped:GetAttribute("HasGrappled") == true then return end
		Remotes.ToggleWallMode:FireServer()
	end
	local ropeLength = label(reelControls, "", UDim2.fromOffset(-36, -22), UDim2.fromOffset(150, 18))
	ropeLength.TextSize, ropeLength.TextXAlignment = 11, Enum.TextXAlignment.Center
	styleReelLabel(ropeLength)
	local shortButton = button(reelControls, "−", UDim2.fromOffset(0, 0), UDim2.fromOffset(34, 36))
	shortButton.Font, shortButton.TextSize = Enum.Font.GothamBold, 22
	make("UIStroke", shortButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local longButton = button(reelControls, "+", UDim2.fromOffset(44, 0), UDim2.fromOffset(34, 36))
	longButton.Font, longButton.TextSize = Enum.Font.GothamBold, 22
	make("UIStroke", longButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	if UIS.KeyboardEnabled and not UIS.TouchEnabled then
		for _, hint in ipairs({{"(Q)", -34}, {"(E)", 84}}) do
			local text = label(reelControls, hint[1], UDim2.fromOffset(hint[2], 0), UDim2.fromOffset(28, 36))
			text.TextSize, text.TextXAlignment = 13, Enum.TextXAlignment.Center
			styleReelLabel(text)
		end
	end
	local reelHint = label(reelControls, "Hold to adjust length", UDim2.fromOffset(-36, 39), UDim2.fromOffset(150, 18))
	reelHint.TextSize, reelHint.TextXAlignment = 11, Enum.TextXAlignment.Center
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
	local wallButton = button(wallControls, "OFF", UDim2.fromOffset(0, 0), UDim2.fromOffset(78, 36), toggleWallMode)
	wallButton.Font, wallButton.TextSize = Enum.Font.GothamBold, 14
	make("UIStroke", wallButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local inventoryOpen = false
	-- SHOP through the coin total. On a phone this stack is scaled to stay above the hotbar.
	local leftStack = make("Frame", screen, {
		Name = "LeftStack", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 18, 0.5, -94),
		Size = UDim2.fromOffset(168, 264), BackgroundTransparency = 1,
	})
	local leftStackScale = make("UIScale", leftStack, {Scale = 1})
	local inventoryButton = button(leftStack, "INV", UDim2.fromOffset(0, 104), UDim2.fromOffset(44, 44), function() inventoryOpen = not inventoryOpen end)
	inventoryButton.Font, inventoryButton.TextSize = Enum.Font.GothamBold, 12
	make("UIStroke", inventoryButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local shopButton = button(leftStack, "SHOP", UDim2.fromOffset(0, 0), UDim2.fromOffset(44, 44))
	shopButton.Name = "ShopButton"
	shopButton.Font = Enum.Font.GothamBold
	shopButton.TextScaled = true
	shopButton.ZIndex = 40
	make("UIPadding", shopButton, {PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)})
	make("UITextSizeConstraint", shopButton, {MinTextSize = 8, MaxTextSize = 12})
	make("UIStroke", shopButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local upgradeButton = button(leftStack, "UPG", UDim2.fromOffset(0, 52), UDim2.fromOffset(44, 44))
	upgradeButton.Name = "UpgradeButton"
	upgradeButton.Font = Enum.Font.GothamBold
	upgradeButton.TextScaled = true
	upgradeButton.ZIndex = 40
	make("UIPadding", upgradeButton, {PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)})
	make("UITextSizeConstraint", upgradeButton, {MinTextSize = 8, MaxTextSize = 12})
	make("UIStroke", upgradeButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local ragdollButton = button(leftStack, "RAG", UDim2.fromOffset(0, 156), UDim2.fromOffset(44, 44), ragdoll)
	ragdollButton.Name = "RagdollButton"
	local coins = make("Frame", leftStack, {
		Name = "Coins", Position = UDim2.fromOffset(0, 208),
		Size = UDim2.fromOffset(168, 56), BackgroundTransparency = 1,
	})
	make("ImageLabel", coins, {
		Name = "Icon", Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1,
		Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
	})
	local coinAmount = label(coins, "0", UDim2.fromOffset(62, 0), UDim2.fromOffset(106, 56))
	coinAmount.Name = "Amount"
	styleReelLabel(coinAmount)
	coinAmount.TextSize = 18
	local function updateCoins()
		coinAmount.Text = tostring(player:GetAttribute("Coins") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(updateCoins)
	updateCoins()
	ragdollButton.Font, ragdollButton.TextSize = Enum.Font.GothamBold, 12
	make("UIStroke", ragdollButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local ragdollBorder = make("UIStroke", ragdollButton, {
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
		styleReelLabel(hint)
	end
	local inventory = require(script.Parent:WaitForChild("CollectionUi")).CreateInventory(leftStack, Remotes.SetGrappleColor)
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
	local escapeGreen = Color3.fromRGB(0, 170, 85)
	-- Bottom-anchored at the old text's bottom edge, so escape buttons grow upward.
	local tetherPanel = make("Frame", screen, {
		Name = "TetherCountdown", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.75, 28),
		Size = UDim2.fromOffset(380, 56), BackgroundColor3 = Color3.fromRGB(27, 42, 53),
		BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
	})
	rounded(tetherPanel)
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
		if method == "robux" then
			local productId = Config.escapeRobuxProductId
			if type(productId) ~= "number" or productId <= 0 then return end
		end
		escapePending = true
		escapeNote = ""
		Remotes.EscapeTether:FireServer(method)
	end
	local coinEscape = button(escapeRow, "", UDim2.fromOffset(0, 0), UDim2.new(0.5, -4, 1, 0), function()
		requestEscape("coins")
	end)
	coinEscape.BackgroundColor3 = escapeGreen
	make("UIListLayout", coinEscape, {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	make("ImageLabel", coinEscape, {
		BackgroundTransparency = 1, Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(16, 16), LayoutOrder = 1,
	})
	local coinEscapeText = make("TextLabel", coinEscape, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = tostring(Config.escapeCoinCost or 30),
		Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), LayoutOrder = 2,
	})
	local robuxEscape = button(escapeRow, utf8.char(0xE002) .. "  " .. tostring(Config.escapeRobuxPrice or 9), UDim2.new(0.5, 4, 0, 0), UDim2.new(0.5, -4, 1, 0), function()
		requestEscape("robux")
	end)
	robuxEscape.BackgroundColor3 = escapeGreen
	robuxEscape.Font = Enum.Font.GothamBold
	robuxEscape.TextSize = 15
	robuxEscape.TextColor3 = Color3.new(1, 1, 1)
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
	local shopScale
	local upgradesOpen = false
	local upgradesWindow
	local adminUi
	local function hideAdmin()
		if adminUi then adminUi.hide() end
	end
	-- The native hotbar is core UI, so it draws above these windows and still takes taps.
	-- Hide it while the shop or upgrades are open, then put it back.
	local function overlayOpen()
		return shopOpen or upgradesOpen
	end
	local function syncHotbar()
		local enabled = not overlayOpen()
		local function apply()
			return pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, enabled)
		end
		if apply() then return end
		task.defer(function()
			if (not overlayOpen()) ~= enabled then return end
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
		Size = UDim2.fromOffset(330, 250), BackgroundColor3 = Color3.fromRGB(39, 51, 65), Visible = false,
	})
	rounded(settingsWindow)
	make("UIStroke", settingsWindow, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.75})
	local settingsScale = make("UIScale", settingsWindow, {Scale = 1})
	local settingsTitle = label(settingsWindow, "Settings", UDim2.fromOffset(16, 10), UDim2.fromOffset(250, 28))
	settingsTitle.Font, settingsTitle.TextSize = Enum.Font.GothamBold, 20
	local closeSettings = button(settingsWindow, "X", UDim2.fromOffset(286, 9), UDim2.fromOffset(32, 30))
	closeSettings.Font = Enum.Font.GothamBold
	local function showSettings(visible)
		settingsOpen = visible
		settingsWindow.Visible = visible
		if visible and codexWindow then
			codexOpen = false
			codexWindow.Visible = false
		end
		if visible then
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
			BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0,
			Font = Enum.Font.BuilderSans, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255),
			LayoutOrder = order,
		})
		make("UICorner", instance, {CornerRadius = UDim.new(1, 0)})
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
	local musicMuted = false
	local menuList = make("Frame", screen, {
		Name = "MenuList", Visible = false, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(168, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.25,
		BorderSizePixel = 0, ZIndex = 20,
	})
	rounded(menuList)
	make("UIStroke", menuList, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.75, Transparency = 0.85})
	make("UIPadding", menuList, {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)})
	make("UIListLayout", menuList, {SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center})
	local function styleMenuEntry(entry)
		local hovered, selected = false, false
		make("UICorner", entry, {CornerRadius = UDim.new(0, 8)})
		local function updateHighlight()
			entry.BackgroundTransparency = (hovered or selected) and 0.9 or 1
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
	adminMark.Font, adminMark.TextSize = Enum.Font.GothamBold, 16
	adminMark.TextXAlignment = Enum.TextXAlignment.Center
	adminMark.ZIndex = 22
	local adminEntryLabel = label(adminEntry, "Admin", UDim2.fromOffset(40, 0), UDim2.new(1, -48, 1, 0))
	adminEntryLabel.Font, adminEntryLabel.TextSize = Enum.Font.BuilderSans, 18
	adminEntryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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
	settingsEntryLabel.Font, settingsEntryLabel.TextSize = Enum.Font.BuilderSans, 18
	settingsEntryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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
	codexEntryLabel.Font, codexEntryLabel.TextSize = Enum.Font.BuilderSans, 18
	codexEntryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	codexEntryLabel.TextYAlignment = Enum.TextYAlignment.Center
	codexEntryLabel.ZIndex = 22
	codexWindow = make("Frame", screen, {
		Name = "CodexWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 420), BackgroundColor3 = Color3.fromRGB(39, 51, 65), Visible = false,
	})
	rounded(codexWindow)
	make("UIStroke", codexWindow, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.75})
	local codexScale = make("UIScale", codexWindow, {Scale = 1})
	local codexTitle = label(codexWindow, "Codex", UDim2.fromOffset(16, 10), UDim2.fromOffset(220, 28))
	codexTitle.Font, codexTitle.TextSize = Enum.Font.GothamBold, 20
	local closeCodex = button(codexWindow, "X", UDim2.new(1, -44, 0, 9), UDim2.fromOffset(32, 30))
	closeCodex.Font = Enum.Font.GothamBold
	require(script.Parent:WaitForChild("CollectionUi")).PopulateCodex(codexWindow)
	local function showCodex(visible)
		codexOpen = visible
		codexWindow.Visible = visible
		if visible then
			settingsOpen = false
			settingsWindow.Visible = false
			hideShop()
			hideUpgrades()
			hideAdmin()
		end
	end
	closeCodex.Activated:Connect(function() showCodex(false) end)
	local function placeMenuList()
		local origin = screen.AbsolutePosition
		local pos = menuButton.AbsolutePosition
		local size = menuButton.AbsoluteSize
		menuList.Position = UDim2.fromOffset(pos.X - origin.X, pos.Y + size.Y - origin.Y + 4)
	end
	local function showMenu(visible)
		menuOpen = visible
		menuList.Visible = visible
		if visible then placeMenuList() end
	end
	local function pointerInside(gui, x, y)
		local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
		return x >= pos.X and x <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y
	end
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
		if not menuOpen then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if pointerInside(menuButton, input.Position.X, input.Position.Y) then return end
		if pointerInside(menuList, input.Position.X, input.Position.Y) then return end
		showMenu(false)
	end)
	GuiService.MenuOpened:Connect(function() showMenu(false) end)

	local showShop
	local shopUi = ShopUi.Mount(screen, function()
		showShop(false)
	end)
	shopWindow = shopUi.window
	shopScale = shopUi.scale
	local function fitShop()
		local camera = workspace.CurrentCamera
		if not camera or not shopScale then return end
		local viewport = camera.ViewportSize
		if viewport.X < 1 or viewport.Y < 1 then return end
		local fitted = math.min((viewport.X - 24) / 680, (viewport.Y - 24) / 520)
		if UIS.TouchEnabled then fitted *= 0.85 end
		shopScale.Scale = math.clamp(fitted, 0.4, 1)
	end
	local function fitLeftStack()
		local camera = workspace.CurrentCamera
		if not camera then return end
		if not UIS.TouchEnabled then
			leftStackScale.Scale = 1
			leftStack.Position = UDim2.new(0, 18, 0.5, -94)
			return
		end
		local viewport = camera.ViewportSize
		local topMargin, bottomMargin, height = 8, 88, 264
		local available = math.max(140, viewport.Y - topMargin - bottomMargin)
		local scale = math.clamp(available / height, 0.55, 0.9)
		leftStackScale.Scale = scale
		local top = topMargin + math.max(0, (available - height * scale) / 2)
		leftStack.Position = UDim2.fromOffset(10, top)
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
		if inventoryOpen then hideUpgrades() end
	end)

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
		Size = UDim2.fromOffset(294, 48), BackgroundTransparency = 1,
	})
	local timeLabel = label(timeControls, "Time of Day", UDim2.fromOffset(0, 0), UDim2.fromOffset(294, 16))
	timeLabel.TextXAlignment, timeLabel.Font = Enum.TextXAlignment.Center, Enum.Font.GothamBold
	local timeTrack = make("TextButton", timeControls, {Position = UDim2.fromOffset(7, 28), Size = UDim2.fromOffset(280, 10), BackgroundColor3 = Color3.fromRGB(20, 29, 38), BorderSizePixel = 0, Text = ""})
	rounded(timeTrack)
	local timeKnob = make("Frame", timeTrack, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0})
	rounded(timeKnob)
	local adjustingTime = false
	local function setLocalTime(position, shouldSave)
		local fraction = math.clamp((position.X - timeTrack.AbsolutePosition.X) / math.max(1, timeTrack.AbsoluteSize.X), 0, 1)
		Lighting.ClockTime = fraction * 24
		timeKnob.Position = UDim2.fromScale(fraction, 0.5)
		timeLabel.Text = string.format("Time of Day  %02d:%02d", math.floor(Lighting.ClockTime) % 24, math.floor((Lighting.ClockTime % 1) * 60))
		if shouldSave then saveSetting("LocalClockTime", Lighting.ClockTime) end
	end
	timeTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then adjustingTime = true setLocalTime(input.Position, true) end
	end)

	local shadowsLabel = label(settingsWindow, "Shadows", UDim2.fromOffset(20, 115), UDim2.fromOffset(220, 32))
	shadowsLabel.Font = Enum.Font.GothamBold
	local shadowsEnabled = Lighting.GlobalShadows
	local shadowsCheckbox = button(settingsWindow, "", UDim2.fromOffset(274, 115), UDim2.fromOffset(32, 32))
	make("UIStroke", shadowsCheckbox, {Color = Color3.fromRGB(255, 255, 255), Thickness = 1})
	local function applyShadows(enabled)
		shadowsEnabled = enabled
		Lighting.GlobalShadows = enabled
		shadowsCheckbox.Text = enabled and "X" or ""
		shadowsCheckbox.BackgroundColor3 = enabled and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(20, 29, 38)
	end
	shadowsCheckbox.Activated:Connect(function()
		applyShadows(not shadowsEnabled)
		saveSetting("ShadowsEnabled", shadowsEnabled, true)
	end)

	local musicControls = make("Frame", settingsWindow, {
		Name = "MusicVolumeControls", Position = UDim2.fromOffset(18, 166),
		Size = UDim2.fromOffset(294, 54), BackgroundTransparency = 1,
	})
	local musicLabel = label(musicControls, "Music Volume", UDim2.fromOffset(0, 0), UDim2.fromOffset(294, 18))
	musicLabel.TextXAlignment, musicLabel.Font = Enum.TextXAlignment.Center, Enum.Font.GothamBold
	local musicTrack = make("TextButton", musicControls, {Position = UDim2.fromOffset(7, 32), Size = UDim2.fromOffset(280, 10), BackgroundColor3 = Color3.fromRGB(20, 29, 38), BorderSizePixel = 0, Text = ""})
	rounded(musicTrack)
	local musicKnob = make("Frame", musicTrack, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0})
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
	UIS.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if adjustingTime then setLocalTime(input.Position, true) end
		if adjustingMusic then setMusicFromPosition(input.Position, true) end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if adjustingTime then saveSetting("LocalClockTime", Lighting.ClockTime, true) end
			if adjustingMusic then saveSetting("MusicVolume", musicVolume, true) end
			adjustingTime, adjustingMusic = false, false
		end
	end)

	local function applySavedSettings()
		local savedTime = player:GetAttribute("LocalClockTime")
		local savedShadows = player:GetAttribute("ShadowsEnabled")
		local savedMusic = player:GetAttribute("MusicVolume")
		if typeof(savedTime) == "number" then
			Lighting.ClockTime = math.clamp(savedTime, 0, 24)
			timeKnob.Position = UDim2.fromScale(Lighting.ClockTime / 24, 0.5)
		end
		timeLabel.Text = string.format("Time of Day  %02d:%02d", math.floor(Lighting.ClockTime) % 24, math.floor((Lighting.ClockTime % 1) * 60))
		if typeof(savedShadows) ~= "boolean" then savedShadows = Lighting.GlobalShadows end
		applyShadows(savedShadows)
		applyMusicVolume(typeof(savedMusic) == "number" and savedMusic or 1)
		applyMuted(player:GetAttribute("MusicMuted") == true)
	end
	for _, key in ipairs({"LocalClockTime", "ShadowsEnabled", "MusicVolume", "MusicMuted"}) do
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
		local escapeExtra = showEscape and 44 or 0
		tetherPanel.Visible = #lines > 0
		tetherPanel.Size = UDim2.fromOffset(380, baseHeight + escapeExtra)
		-- On a phone the text already sits clear of the hotbar, so lift by the
		-- button row instead of drawing the buttons down into it.
		local lift = (showEscape and UIS.TouchEnabled) and escapeExtra or 0
		tetherPanel.Position = UDim2.new(0.5, 0, 0.75, 28 - lift)
		tetherText.Position = UDim2.fromOffset(12, 4)
		tetherText.Size = UDim2.new(1, -24, 0, baseHeight - 8)
		tetherText.Text = table.concat(lines, "\n")
		escapeRow.Visible = showEscape
		coinEscapeText.Text = escapeNote ~= "" and escapeNote or tostring(Config.escapeCoinCost or 30)
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
		ragdollBorder.Enabled = humanoid ~= nil and humanoid.Health > 0
			and humanoid:GetAttribute("Ragdolled") == true
			and humanoid:GetAttribute("ManualRagdoll") == true
			and not humanoid:GetAttribute("CapsuleLocked")
		if ragdollBorder.Enabled then
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
			reelScale.Scale, wallScale.Scale = scale, scale
			tetherScale.Scale = math.clamp(math.min(viewport.X / 480, viewport.Y / 800), 0.55, 1)
			local settingsUiScale = math.clamp(math.min(viewport.X / 800, viewport.Y / 600), 0.7, 1)
			settingsScale.Scale = settingsUiScale
			codexScale.Scale = settingsUiScale
			fitShop()
			fitLeftStack()
			upgradeUi.fit()
			if adminUi then adminUi.fit() end
		end
		if menuOpen then placeMenuList() end
		if currentRope and not currentRope.Parent then grapple() end
		local equipped = tool()
		reelControls.Visible = currentRope ~= nil and equipped ~= nil
		wallControls.Visible = equipped ~= nil
		inventoryButton.Visible = player.Character ~= nil
		ragdollButton.Visible = player.Character ~= nil
		inventory.Visible = player.Character ~= nil and inventoryOpen
		local wallMode = equipped and equipped:GetAttribute("WallMode") == true
		wallButton.Text = wallMode and "ON" or "OFF"
		wallButton.BackgroundColor3 = wallMode and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(178, 70, 70)
		if currentRope and not shorten and not lengthen then displayLength = currentRope.Length end
		ropeLength.Text = currentRope and string.format("%.1f studs", displayLength) or ""
	end)
end
return M

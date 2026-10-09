local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Assets = require(storage:WaitForChild("Assets"))
local Palettes = require(storage:WaitForChild("ItemColors"))
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
	local struggling = false
	local function tool()
		local candidate = player.Character and player.Character:FindFirstChild(Config.toolName)
		return candidate and candidate:IsA("Tool") and candidate or nil
	end
	local function reelStep()
		return displayLength * (Config.ropeLengthFraction or 0.05)
	end
	local function change(delta)
		if not currentRope or not currentRope.Parent then return end
		local minimum = currentRope:GetAttribute("PlayerGrapple") and Config.playerMinDragDistance or Config.minRopeLength
		displayLength = math.clamp(displayLength + delta, minimum, Config.maxRopeLength)
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
			or os.clock() - lastFlop < (Config.flopCooldown or 2.2) then return end
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
	local flopButton = button(screen, "FLOP", UDim2.new(1, -160, 1, -150), UDim2.fromOffset(52, 52), flop)
	flopButton.Name, flopButton.Visible = "FlopButton", false
	flopButton.Font = Enum.Font.GothamBold
	make("UIStroke", flopButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 1})
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
		if tool() and not struggling then Remotes.ToggleWallMode:FireServer() end
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
	local palette = Palettes.Order
	local inventoryOpen, inventoryTab = false, "Gun"
	local inventoryButton = button(screen, "INV", UDim2.new(0, 18, 0.5, -22), UDim2.fromOffset(44, 44), function() inventoryOpen = not inventoryOpen end)
	inventoryButton.Font, inventoryButton.TextSize = Enum.Font.GothamBold, 12
	make("UIStroke", inventoryButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local ragdollButton = button(screen, "RAG", UDim2.new(0, 18, 0.5, 30), UDim2.fromOffset(44, 44), ragdoll)
	ragdollButton.Name = "RagdollButton"
	local coins = make("Frame", screen, {
		Name = "Coins", Position = UDim2.new(0, 18, 0.5, 82),
		Size = UDim2.fromOffset(150, 36), BackgroundTransparency = 1,
	})
	make("ImageLabel", coins, {
		Name = "Icon", Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1,
		Image = Assets.Coins, ScaleType = Enum.ScaleType.Fit,
	})
	local coinAmount = label(coins, "0", UDim2.fromOffset(42, 0), UDim2.fromOffset(108, 36))
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
	local inventory = make("Frame", screen, {Name = "GrappleInventory", Position = UDim2.new(0, 72, 0.5, -104), Size = UDim2.fromOffset(184, 208), BackgroundColor3 = Color3.fromRGB(39, 51, 65), Visible = false})
	rounded(inventory)
	make("UIStroke", inventory, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local gunTab = button(inventory, "Gun", UDim2.fromOffset(10, 10), UDim2.fromOffset(52, 28))
	local ropeTab = button(inventory, "Rope", UDim2.fromOffset(66, 10), UDim2.fromOffset(52, 28))
	local bombTab = button(inventory, "Bomb", UDim2.fromOffset(122, 10), UDim2.fromOffset(52, 28))
	local colorButtons = {}
	for index, entry in ipairs(palette) do
		local colorName, color = entry, Palettes.Swatches.Gun[entry]
		local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
		local swatch = button(inventory, colorName, UDim2.fromOffset(10 + column * 42, 48 + row * 48), UDim2.fromOffset(36, 42), function()
			Remotes.SetGrappleColor:FireServer(inventoryTab, inventoryTab == "Bomb" and colorName == "Teal" and "Mint" or colorName)
		end)
		swatch.BackgroundColor3, swatch.TextColor3, swatch.TextSize = color, Color3.fromRGB(27, 42, 53), 8
		make("UIStroke", swatch, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
		table.insert(colorButtons, swatch)
	end
	gunTab.Activated:Connect(function() inventoryTab = "Gun" end)
	local rainbowButton = button(inventory, "Rainbow", UDim2.fromOffset(10, 198), UDim2.fromOffset(164, 30), function()
		Remotes.SetGrappleColor:FireServer(inventoryTab, "Rainbow")
	end)
	rainbowButton.Visible = false
	rainbowButton.Font = Enum.Font.GothamBold
	rainbowButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	make("UIGradient", rainbowButton, {Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 230, 110)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 140, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 255)),
	})})
	make("UIStroke", rainbowButton, {Color = Color3.fromRGB(27, 42, 53), Thickness = 1})
	ropeTab.Activated:Connect(function() inventoryTab = "Rope" end)
	bombTab.Activated:Connect(function() inventoryTab = "Bomb" end)
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
	local escape = make("Frame", screen, {
		Name = "Escape", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(380, 124), BackgroundColor3 = Color3.fromRGB(39, 22, 30), Visible = false,
	})
	rounded(escape)
	local escapeScale = make("UIScale", escape, {Scale = 1})
	local escapeTitle = label(escape, "YOU'VE BEEN GRAPPLED", UDim2.fromOffset(18, 10), UDim2.fromOffset(344, 24), Color3.fromRGB(255, 158, 158))
	local escapeTrack = make("Frame", escape, {Position = UDim2.fromOffset(18, 43), Size = UDim2.fromOffset(344, 7), BackgroundColor3 = Color3.fromRGB(80, 44, 52), BorderSizePixel = 0})
	local escapeFill = make("Frame", escapeTrack, {Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 158, 158), BorderSizePixel = 0})
	local function struggle()
		if struggling then Remotes.StruggleInput:FireServer() end
	end
	local escapeButton = button(escape, UIS.TouchEnabled and "Tap to struggle" or "Press Space to struggle", UDim2.fromOffset(18, 66), UDim2.fromOffset(344, 40))
	escapeButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then struggle() end
	end)
	local ACTION = "GrappleHUD_Struggle"
	local function stopStruggle()
		struggling = false
		escape.Visible = false
		CAS:UnbindAction(ACTION)
	end
	Remotes.HasBeenGrappled.OnClientEvent:Connect(function(attacker)
		stopStruggle()
		if not attacker then return end
		struggling = true
		escape.Visible = true
		escapeTitle.Text = "GRAPPLED BY " .. string.upper(attacker.DisplayName)
		escapeFill.Size = UDim2.fromScale(0, 1)
		CAS:BindActionAtPriority(ACTION, function(_, state)
			if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
			if state == Enum.UserInputState.Begin then struggle() flop() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Space)
	end)
	Remotes.StruggleProgress.OnClientEvent:Connect(function(progress, target)
		if struggling then escapeFill.Size = UDim2.fromScale(math.clamp(progress / math.max(1, target), 0, 1), 1) end
	end)
	local settingsOpen = false
	local settingsWindow
	local settingsButton = make("ImageButton", screen, {
		Name = "SettingsButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromRGB(39, 51, 65),
		Image = Assets.Settings, ScaleType = Enum.ScaleType.Fit, AutoButtonColor = true,
	})
	rounded(settingsButton)
	make("UIStroke", settingsButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local settingsButtonScale = make("UIScale", settingsButton, {Scale = 1})
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
	end
	settingsButton.Activated:Connect(function() showSettings(not settingsOpen) end)
	closeSettings.Activated:Connect(function() showSettings(false) end)

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
	-- Keep strong references to the Studio-authored values. A weak table can
	-- forget an Instance key and accidentally use an already-scaled volume as
	-- the new baseline, causing rapid slider movement to compound toward zero.
	local musicBaseVolumes = {}
	local function applyMusicSound(instance)
		if not instance:IsA("Sound") then return end
		if musicBaseVolumes[instance] == nil then musicBaseVolumes[instance] = instance.Volume end
		instance.Volume = math.clamp(musicBaseVolumes[instance] * musicVolume, 0, 10)
	end
	local function applyMusicFolder(folder)
		for _, instance in ipairs(folder:GetDescendants()) do applyMusicSound(instance) end
		folder.DescendantAdded:Connect(applyMusicSound)
	end
	local musicFolder = storage:FindFirstChild("Music")
	if musicFolder then applyMusicFolder(musicFolder) end
	storage.ChildAdded:Connect(function(child)
		if child.Name == "Music" then applyMusicFolder(child) end
	end)
	local function applyMusicVolume(value)
		musicVolume = math.clamp(value, 0, 1)
		musicKnob.Position = UDim2.fromScale(musicVolume, 0.5)
		musicLabel.Text = string.format("Music Volume  %d%%", math.floor(musicVolume * 100 + 0.5))
		local folder = storage:FindFirstChild("Music")
		if folder then
			for _, instance in ipairs(folder:GetDescendants()) do applyMusicSound(instance) end
		end
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
		applyShadows(typeof(savedShadows) == "boolean" and savedShadows or Lighting.GlobalShadows)
		applyMusicVolume(typeof(savedMusic) == "number" and savedMusic or 1)
	end
	for _, key in ipairs({"LocalClockTime", "ShadowsEnabled", "MusicVolume"}) do
		player:GetAttributeChangedSignal(key):Connect(applySavedSettings)
	end
	applySavedSettings()
	local function grapple(target, rope)
		currentRope = rope
		displayLength = rope and rope.Length or 0
		shorten, lengthen = false, false
	end
	Remotes.GrappledPlayer.OnClientEvent:Connect(grapple)
	Remotes.GrappledWall.OnClientEvent:Connect(grapple)
	CAS:BindActionAtPriority("GrappleHUD_TargetMode", function(_, state)
		if UIS:GetFocusedTextBox() or not tool() or struggling then return Enum.ContextActionResult.Pass end
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
		stopStruggle()
		grapple()
		if characterConnection then characterConnection:Disconnect() end
		for _, instance in ipairs(character:GetChildren()) do watchTool(instance) end
		characterConnection = character.ChildAdded:Connect(watchTool)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid:GetAttributeChangedSignal("GrappledBy"):Connect(function()
			if humanoid:GetAttribute("GrappledBy") == nil then stopStruggle() end
		end)
		humanoid.Died:Once(function() stopStruggle() grapple() end)
	end
	player.CharacterAdded:Connect(characterAdded)
	player.CharacterRemoving:Connect(function() stopStruggle() grapple() end)
	if player.Character then task.spawn(characterAdded, player.Character) end
	local accumulator, uiAccumulator = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		flopButton.Visible = UIS.TouchEnabled and FlopMotion.CanFlop(player.Character)
		flopButton.Text = os.clock() - lastFlop < (Config.flopCooldown or 2.2) and "..." or "FLOP"
		local touchGui = playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if jump and jump:IsA("GuiObject") then
			flopButton.Position = UDim2.fromOffset(jump.AbsolutePosition.X - screen.AbsolutePosition.X - 60,
				jump.AbsolutePosition.Y - screen.AbsolutePosition.Y + (jump.AbsoluteSize.Y - 52) / 2)
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
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
			escapeScale.Scale = math.clamp(math.min(viewport.X / 480, viewport.Y / 800), 0.55, 1)
			local settingsUiScale = math.clamp(math.min(viewport.X / 800, viewport.Y / 600), 0.7, 1)
			settingsScale.Scale = settingsUiScale
			settingsButtonScale.Scale = math.clamp(math.min(viewport.X / 800, viewport.Y / 450), 0.75, 1.1)
		end
		if currentRope and not currentRope.Parent then grapple() end
		local equipped = tool()
		reelControls.Visible = currentRope ~= nil and equipped ~= nil
		wallControls.Visible = equipped ~= nil
		inventoryButton.Visible = player.Character ~= nil
		ragdollButton.Visible = player.Character ~= nil
		inventory.Visible = player.Character ~= nil and inventoryOpen
		rainbowButton.Visible = true
		for index, swatch in ipairs(colorButtons) do
			local name = palette[index]
			swatch.Text = inventoryTab == "Bomb" and name == "Teal" and "Mint" or name
			swatch.Visible = Palettes[inventoryTab][name] ~= nil
			if swatch.Visible then swatch.BackgroundColor3 = Palettes.Swatches[inventoryTab][name] end
		end
		rainbowButton.Position = UDim2.fromOffset(10, inventoryTab == "Bomb" and 198 or 246)
		inventory.Size = UDim2.fromOffset(184, inventoryTab == "Bomb" and 238 or 286)
		gunTab.BackgroundColor3 = inventoryTab == "Gun" and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(178, 70, 70)
		ropeTab.BackgroundColor3 = inventoryTab == "Rope" and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(178, 70, 70)
		bombTab.BackgroundColor3 = inventoryTab == "Bomb" and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(178, 70, 70)
		local wallMode = equipped and equipped:GetAttribute("WallMode") == true
		wallButton.Text = wallMode and "ON" or "OFF"
		wallButton.BackgroundColor3 = wallMode and Color3.fromRGB(72, 165, 92) or Color3.fromRGB(178, 70, 70)
		if currentRope and not shorten and not lengthen then displayLength = currentRope.Length end
		ropeLength.Text = currentRope and string.format("%.1f studs", displayLength) or ""
	end)
end
return M

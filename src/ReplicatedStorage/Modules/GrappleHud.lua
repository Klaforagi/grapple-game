local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Remotes = require(script.Parent:WaitForChild("GrappleRemotes"))
local ToolClient = require(script.Parent:WaitForChild("GrappleToolClient"))
local ToolSetup = require(script.Parent:WaitForChild("GrappleToolSetup"))
local M = {}

function M.Init()
	if M.started then return end
	M.started = true
	require(script.Parent.RagdollService).InitClient()
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
	local function ragdoll() Remotes.ToggleRagdoll:FireServer() end
	-- A compact touch-only reel replaces the former full-screen grapple panel.
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
	local ropeLength = label(reelControls, "", UDim2.fromOffset(-36, -22), UDim2.fromOffset(150, 18))
	ropeLength.TextSize, ropeLength.TextXAlignment = 11, Enum.TextXAlignment.Center
	styleReelLabel(ropeLength)
	local shortButton = button(reelControls, "−", UDim2.fromOffset(0, 0), UDim2.fromOffset(34, 36))
	shortButton.Font, shortButton.TextSize = Enum.Font.GothamBold, 22
	make("UIStroke", shortButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local longButton = button(reelControls, "+", UDim2.fromOffset(44, 0), UDim2.fromOffset(34, 36))
	longButton.Font, longButton.TextSize = Enum.Font.GothamBold, 22
	make("UIStroke", longButton, {Color = Color3.fromRGB(255, 255, 255), Thickness = 0.5})
	local reelHint = label(reelControls, "Hold to adjust length", UDim2.fromOffset(-36, 39), UDim2.fromOffset(150, 18))
	reelHint.TextSize, reelHint.TextXAlignment = 11, Enum.TextXAlignment.Center
	styleReelLabel(reelHint)
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
		Name = "Escape", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
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
	local escapeButton = button(escape, UIS.TouchEnabled and "Tap here to escape" or "Press Space to escape", UDim2.fromOffset(18, 66), UDim2.fromOffset(344, 40))
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
			if state == Enum.UserInputState.Begin then struggle() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Space)
	end)
	Remotes.StruggleProgress.OnClientEvent:Connect(function(progress, target)
		if struggling then escapeFill.Size = UDim2.fromScale(math.clamp(progress / math.max(1, target), 0, 1), 1) end
	end)
	local function grapple(target, rope)
		currentRope = rope
		displayLength = rope and rope.Length or 0
		shorten, lengthen = false, false
	end
	Remotes.GrappledPlayer.OnClientEvent:Connect(grapple)
	Remotes.GrappledWall.OnClientEvent:Connect(grapple)
	CAS:BindActionAtPriority("GrappleHUD_TargetMode", function(_, state)
		if UIS:GetFocusedTextBox() or not tool() or struggling then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then Remotes.ToggleWallMode:FireServer() end
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
			reelScale.Scale = math.clamp(math.min(viewport.X / 800, viewport.Y / 450), 0.7, 1.2)
		end
		if currentRope and not currentRope.Parent then grapple() end
		reelControls.Visible = UIS.TouchEnabled and currentRope ~= nil and tool() ~= nil
		if currentRope and not shorten and not lengthen then displayLength = currentRope.Length end
		ropeLength.Text = currentRope and string.format("%.1f studs", displayLength) or ""
	end)
end
return M

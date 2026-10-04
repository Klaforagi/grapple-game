local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Remotes = require(script.Parent:WaitForChild("GrappleRemotes"))
local ToolClient = require(script.Parent:WaitForChild("GrappleToolClient"))
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
	local accent = Color3.fromRGB(104, 231, 206)
	local function rounded(frame)
		make("UICorner", frame, {CornerRadius = UDim.new(0, 12)})
	end
	local panel = make("Frame", screen, {
		Name = "Controls", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -24),
		Size = UDim2.fromOffset(380, 214), BackgroundColor3 = Color3.fromRGB(18, 23, 32), BackgroundTransparency = 0.08,
	})
	rounded(panel)
	make("UIStroke", panel, {Color = Color3.fromRGB(61, 76, 90), Thickness = 1})
	local scale = make("UIScale", panel, {Scale = 1})
	local responsiveText = {}
	local function label(parent, text, position, size, color)
		local instance = make("TextLabel", parent, {
			Text = text, Position = position, Size = size, BackgroundTransparency = 1,
			TextColor3 = color or Color3.fromRGB(232, 240, 247), TextSize = 15, Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		table.insert(responsiveText, {instance = instance, size = 15})
		return instance
	end
	label(panel, "GRAPPLE", UDim2.fromOffset(18, 10), UDim2.fromOffset(170, 24), accent)
	local mode = label(panel, "", UDim2.fromOffset(196, 10), UDim2.fromOffset(166, 24))
	mode.TextXAlignment = Enum.TextXAlignment.Right
	local status = label(panel, "", UDim2.fromOffset(18, 39), UDim2.fromOffset(344, 22))
	local length = label(panel, "", UDim2.fromOffset(18, 67), UDim2.fromOffset(344, 20))
	local track = make("Frame", panel, {Position = UDim2.fromOffset(18, 93), Size = UDim2.fromOffset(344, 5), BackgroundColor3 = Color3.fromRGB(45, 57, 70), BorderSizePixel = 0})
	local fill = make("Frame", track, {Size = UDim2.fromScale(0, 1), BackgroundColor3 = accent, BorderSizePixel = 0})
	local function button(parent, text, position, size, callback)
		local b = make("TextButton", parent, {
			Text = text, Position = position, Size = size, BackgroundColor3 = Color3.fromRGB(39, 51, 65),
			TextColor3 = Color3.fromRGB(234, 244, 250), TextSize = 13, Font = Enum.Font.GothamMedium, AutoButtonColor = true,
		})
		table.insert(responsiveText, {instance = b, size = 13})
		rounded(b)
		if callback then b.Activated:Connect(callback) end
		return b
	end
	local currentRope, targetName
	local displayLength = 0
	local shorten, lengthen = false, false
	local struggling = false
	local function tool()
		local candidate = player.Character and player.Character:FindFirstChild(Config.toolName)
		return candidate and candidate:IsA("Tool") and candidate or nil
	end
	local function reelStep()
		return Config.ropeLengthStep
	end
	local function change(delta)
		if not currentRope or not currentRope.Parent then return end
		local minimum = currentRope:GetAttribute("PlayerGrapple") and Config.playerMinDragDistance or Config.minRopeLength
		displayLength = math.clamp(displayLength + delta, minimum, Config.maxRopeLength)
		Remotes.ChangeLength:FireServer(displayLength)
	end
	local function toggleMode()
		if tool() and not struggling then Remotes.ToggleWallMode:FireServer() end
	end
	local function ragdoll() Remotes.ToggleRagdoll:FireServer() end
	local shortButton = button(panel, Config.shortenRope.Name .. "  Reel in", UDim2.fromOffset(18, 110), UDim2.fromOffset(167, 36))
	local longButton = button(panel, Config.lengthenRope.Name .. "  Let out", UDim2.fromOffset(195, 110), UDim2.fromOffset(167, 36))
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
	local modeButton = button(panel, Config.toggleWallMode.Name .. "  Target mode", UDim2.fromOffset(18, 154), UDim2.fromOffset(167, 36), toggleMode)
	local ragdollButton = button(panel, Config.ragdollKeybind.Name .. "  Ragdoll", UDim2.fromOffset(195, 154), UDim2.fromOffset(167, 36), ragdoll)
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
		targetName = target and (target:IsA("Model") and target.Name or "Wall") or nil
		displayLength = rope and rope.Length or 0
		shorten, lengthen = false, false
	end
	Remotes.GrappledPlayer.OnClientEvent:Connect(grapple)
	Remotes.GrappledWall.OnClientEvent:Connect(grapple)
	CAS:BindActionAtPriority("GrappleHUD_TargetMode", function(_, state)
		if UIS:GetFocusedTextBox() or not tool() or struggling then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then toggleMode() end
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
		if instance:IsA("Tool") and instance.Name == Config.toolName then ToolClient.Init(instance) end
	end
	local backpack = player:WaitForChild("Backpack")
	for _, instance in ipairs(backpack:GetChildren()) do watchTool(instance) end
	backpack.ChildAdded:Connect(watchTool)
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
		if accumulator >= 1 / 30 then
			accumulator %= 1 / 30
			if shorten ~= lengthen then change((shorten and -1 or 1) * reelStep()) end
		end
		uiAccumulator += dt
		if uiAccumulator < 0.1 then return end
		uiAccumulator = 0
		local camera = workspace.CurrentCamera
		local s = 1
		local isPhone = false
		if camera then
			local viewport = camera.ViewportSize
			local widthScale = math.clamp((viewport.X - 32) / 380, 0.5, 1)
			isPhone = UIS.TouchEnabled and math.min(viewport.X, viewport.Y) < 600
			-- On phones, make the panel roughly 40% of the viewport width. Larger
			-- touch devices retain the desktop layout.
			local touchWidthScale = isPhone and math.clamp(viewport.X * 0.4 / 380, 0.4, 0.55) or 1
			local heightScale = math.clamp(viewport.Y * 0.4 / 214, 0.5, 1)
			s = math.min(widthScale, touchWidthScale, heightScale)
		end
		scale.Scale, escapeScale.Scale = s, s
		local compactHud = isPhone
		local textScale = compactHud and math.min(2.25, 1 / s) or 1
		for _, text in ipairs(responsiveText) do
			text.instance.TextSize = math.round(text.size * textScale)
		end
		local equipped = tool()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local ragdolled = humanoid ~= nil and humanoid:GetAttribute("Ragdolled") == true
		mode.Text = equipped and (equipped:GetAttribute("WallMode") and (compactHud and "WALL" or "WALL MODE") or (compactHud and "PLAYER" or "PLAYER MODE")) or (compactHud and "OFF" or "UNEQUIPPED")
		shortButton.Text = compactHud and (Config.shortenRope.Name .. "  In") or (Config.shortenRope.Name .. "  Reel in")
		longButton.Text = compactHud and (Config.lengthenRope.Name .. "  Out") or (Config.lengthenRope.Name .. "  Let out")
		modeButton.Text = compactHud and (Config.toggleWallMode.Name .. "  Mode") or (Config.toggleWallMode.Name .. "  Target mode")
		ragdollButton.Text = compactHud and (Config.ragdollKeybind.Name .. "  Rag") or (Config.ragdollKeybind.Name .. "  Ragdoll")
		if currentRope and not currentRope.Parent then grapple() end
		panel.Visible = equipped ~= nil or currentRope ~= nil or ragdolled
		if currentRope and not shorten and not lengthen then displayLength = currentRope.Length end
		status.Text = targetName and ((compactHud and "Tethered: " or "Connected to ") .. targetName)
			or ragdolled and (struggling and (UIS.TouchEnabled and "Grappled / tap to escape" or "Grappled / press Space to escape") or (compactHud and (Config.ragdollKeybind.Name .. " to recover") or Config.ragdollKeybind.Name .. " / Ragdoll button to recover"))
			or equipped and equipped:GetAttribute("InUse") and (compactHud and "Firing..." or "Hook in flight...")
			or (compactHud and "Tap to fire" or "Click to fire / click again to release")
		length.Text = currentRope and string.format(compactHud and "%.1f studs" or "Rope length  %.1f studs", displayLength)
			or (compactHud and "Aim at player" or "Aim at a player to grapple")
		fill.Size = UDim2.fromScale(math.clamp(displayLength / Config.maxRopeLength, 0, 1), 1)
	end)
end
return M

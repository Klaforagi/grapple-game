local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local CrispFit = require(script.Parent:WaitForChild("CrispFit"))

local INK = Style.Text
local MUTED = Style.Muted
local FIELD = Style.Slot
local GREEN = Style.Action
local RED = Style.Danger
local TAB = Style.ButtonColor
local TAB_ON = Style.Selected or Style.Header

local M = {}

local function make(class, parent, props)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function corner(parent, radius)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius or 8)})
end

local function pad(parent, left)
	make("UIPadding", parent, {
		PaddingLeft = UDim.new(0, left or 10), PaddingRight = UDim.new(0, left or 10),
	})
end

local function outlineField(box)
	box.BackgroundColor3 = FIELD
	box.TextColor3 = INK
	box.PlaceholderColor3 = MUTED
	box.TextStrokeColor3 = Style.Ink
	box.TextStrokeTransparency = 0.55
	make("UIStroke", box, {Color = Style.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end

local function field(parent, name, placeholder, order)
	local box = make("TextBox", parent, {
		Name = name, PlaceholderText = placeholder, Text = "", ClearTextOnFocus = false,
		BackgroundColor3 = FIELD, BorderSizePixel = 0, TextColor3 = INK, PlaceholderColor3 = MUTED,
		Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, ClipsDescendants = true,
	})
	corner(box, 6)
	outlineField(box)
	pad(box, 10)
	return box
end

local function actionButton(parent, name, text, order, color)
	local button = Style.Button(parent, text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 36), color or GREEN)
	button.Name = name
	button.LayoutOrder = order
	button.TextSize = 16
	return button
end

local function paintTab(button, on)
	Style.Recolor(button, on and TAB_ON or TAB)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = on and Style.Accent or Style.Ink end
end

local function headshot(userId)
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then return "" end
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
end

local function playerLabel(entry)
	return tostring(entry.displayName or entry.username or "Player") .. "  @" .. tostring(entry.username or "Unknown")
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local secs = seconds % 60
	if hours > 0 then return string.format("%dh %dm", hours, minutes) end
	if minutes > 0 then return string.format("%dm %ds", minutes, secs) end
	return string.format("%ds", secs)
end

local function profileText(profile)
	local lines = {
		tostring(profile.userId),
		tostring(profile.displayName or "Player") .. " (@" .. tostring(profile.username or "Unknown") .. ")",
		profile.online and "In this server" or "Offline",
		profile.admin and "Admin" or "Not an admin",
		"Coins  " .. tostring(profile.coins or 0) .. " held, " .. tostring(profile.coinsEarned or 0) .. " lifetime",
		"Kills  " .. tostring(profile.kills or 0),
		"Played  " .. formatTime(profile.playedSeconds),
		"Hook Speed  rank " .. tostring(profile.speed or 0),
		"Hook Distance  rank " .. tostring(profile.distance or 0),
		"Tether Duration  rank " .. tostring(profile.duration or 0),
		"Tether Resistance  rank " .. tostring(profile.resistance or 0),
		"Gun  " .. tostring(profile.gun or "Default"),
		"Rope  " .. tostring(profile.rope or "Default"),
		"Bomb  " .. tostring(profile.bomb or "Default"),
		profile.banned and ("Banned  " .. (profile.banReason ~= "" and profile.banReason or "no reason")) or "Not banned",
	}
	return table.concat(lines, "\n")
end

function M.Mount(screen, onOpen)
	local player = Players.LocalPlayer
	local requestRemote, resultRemote
	local window = make("Frame", screen, {
		Name = "AdminWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 560), BackgroundColor3 = Style.Panel, BorderSizePixel = 0,
		Visible = false, ZIndex = 18, ClipsDescendants = true,
	})
	Style.Surface(window, Style.Panel, 8)
	local scale = make("UIScale", window, {Scale = 1})
	local header = make("Frame", window, {Name = "Header", Size = UDim2.new(1, 0, 0, 52), ZIndex = 19})
	Style.Surface(header, Style.Header, 8)
	local title = make("TextLabel", header, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "ADMIN",
		Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(220, 32),
		Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 20,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.45,
	})
	local close = Style.Button(header, "X", UDim2.new(1, -52, 0, 8), UDim2.fromOffset(38, 36), RED)
	close.Name = "Close"
	close.ZIndex = 20

	local tabRow = make("Frame", window, {
		Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 32),
	})
	make("UIListLayout", tabRow, {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local pages = make("Frame", window, {
		Name = "Pages", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 100),
		Size = UDim2.new(1, -24, 1, -144),
	})
	local status = make("TextLabel", window, {
		Name = "Status", BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		Position = UDim2.new(0, 12, 1, -36), Size = UDim2.new(1, -24, 0, 28),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = MUTED,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.55,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local function column(parent)
		make("UIListLayout", parent, {
			Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		})
		return parent
	end

	local pageList = {}
	local function addPage(name)
		local page = make("Frame", pages, {
			Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false,
		})
		column(page)
		pageList[name] = page
		return page
	end

	local coinsPage = addPage("coins")
	local coinUser = field(coinsPage, "UserId", "User id", 1)
	local coinAmount = field(coinsPage, "Amount", "Amount", 2)
	local give = actionButton(coinsPage, "Give", "Give Coins", 3, GREEN)
	local coinNote = make("TextLabel", coinsPage, {
		BackgroundTransparency = 1, Text = "Adds to the coins they are holding. Lifetime coins and the leaderboard stay the same.",
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = MUTED,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.55, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 4,
	})

	local lookupPage = addPage("lookup")
	local lookupUser = field(lookupPage, "User", "User id or username", 1)
	local loadPlayer = actionButton(lookupPage, "Load", "Load Player", 2, GREEN)
	local resultScroll = make("ScrollingFrame", lookupPage, {
		Name = "Result", BackgroundColor3 = Style.Ink, BackgroundTransparency = 0.28, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 300), LayoutOrder = 3, ScrollBarThickness = 4,
		ScrollBarImageColor3 = MUTED,
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Active = true,
	})
	corner(resultScroll, 6)
	make("UIStroke", resultScroll, {Color = Style.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	make("UIPadding", resultScroll, {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	})
	make("UIListLayout", resultScroll, {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder})
	local resultHead = make("Frame", resultScroll, {
		Name = "Head", BackgroundTransparency = 1, Visible = false,
		Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1,
	})
	local resultAvatar = make("ImageLabel", resultHead, {
		Name = "Avatar", BackgroundColor3 = Color3.fromRGB(40, 52, 66), BorderSizePixel = 0,
		Size = UDim2.fromOffset(36, 36), ScaleType = Enum.ScaleType.Crop, Image = "",
		ClipsDescendants = true,
	})
	make("UICorner", resultAvatar, {CornerRadius = UDim.new(1, 0)})
	local resultName = make("TextLabel", resultHead, {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -46, 1, 0),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- A text box so the profile can be highlighted and copied. Typing is ignored.
	local resultText = make("TextBox", resultScroll, {
		Name = "Text", BackgroundTransparency = 1, Text = "Search by user id or username.",
		ClearTextOnFocus = false, TextEditable = true, TextWrapped = true,
		Font = Enum.Font.Gotham, TextSize = 15, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
	})
	local resultLocked = resultText.Text
	local function hideLookupFace()
		resultHead.Visible = false
		resultAvatar.Image = ""
		resultName.Text = ""
	end
	local function showLookupFace(profile)
		local image = headshot(profile.userId)
		if image == "" then
			hideLookupFace()
			return
		end
		resultAvatar.Image = image
		resultName.Text = playerLabel(profile)
		resultHead.Visible = true
	end
	local function setResult(text)
		resultLocked = text
		resultText.Text = text
	end
	resultText:GetPropertyChangedSignal("Text"):Connect(function()
		if resultText.Text ~= resultLocked then resultText.Text = resultLocked end
	end)

	local banPage = addPage("ban")
	local banUser = field(banPage, "User", "User id or username", 1)
	local banReason = field(banPage, "Reason", "Reason (optional)", 2)
	local banButton = actionButton(banPage, "Ban", "Ban", 3, RED)
	local unbanButton = actionButton(banPage, "Unban", "Unban", 4, TAB_ON)
	make("TextLabel", banPage, {
		BackgroundTransparency = 1, Text = "A banned player is kicked and cannot rejoin. Admins cannot be banned.",
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = MUTED,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.55, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 5,
	})

	local resetPage = addPage("reset")
	local resetUser = field(resetPage, "User", "User id or username", 1)
	local resetCoins = actionButton(resetPage, "ResetCoins", "Reset Coins", 2, RED)
	local resetKills = actionButton(resetPage, "ResetKills", "Reset Kills", 3, RED)
	local resetTime = actionButton(resetPage, "ResetTime", "Reset Play Time", 4, RED)
	local resetRanks = actionButton(resetPage, "ResetRanks", "Reset Upgrades", 5, RED)
	local resetAll = actionButton(resetPage, "ResetAll", "Reset All Stats", 6, Color3.fromRGB(140, 36, 36))
	make("TextLabel", resetPage, {
		BackgroundTransparency = 1,
		Text = "Reset Coins clears held coins and lifetime coins. Reset All also clears kills, play time, and upgrade ranks.",
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = MUTED,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.55, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 7,
	})

	local colorPage = addPage("colors")
	local colorUser = field(colorPage, "User", "User id or username", 1)
	local targetRow = make("Frame", colorPage, {
		Name = "Targets", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2,
	})
	make("UIListLayout", targetRow, {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local selectedTarget = "Gun"
	local targetButtons = {}
	for index, targetName in ipairs({"Gun", "Rope", "Bomb"}) do
		local button = Style.Button(targetRow, targetName, UDim2.fromOffset(0, 0), UDim2.new(1 / 3, -4, 1, 0), index == 1 and TAB_ON or TAB)
		button.Name = targetName
		button.TextSize = 16
		button.LayoutOrder = index
		paintTab(button, index == 1)
		targetButtons[targetName] = button
		button.Activated:Connect(function()
			selectedTarget = targetName
			for other, otherButton in pairs(targetButtons) do
				paintTab(otherButton, other == targetName)
			end
		end)
	end
	local colorName = field(colorPage, "Color", "Red, Gold, Rainbow, Mint", 3)
	local applyColor = actionButton(colorPage, "Apply", "Give Cosmetic", 4, GREEN)
	make("TextLabel", colorPage, {
		BackgroundTransparency = 1,
		Text = "Adds one copy to their inventory without equipping it. Uses the gun, rope, and bomb palette names, including Rainbow.",
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = MUTED,
		TextStrokeColor3 = Style.Ink, TextStrokeTransparency = 0.55, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 5,
	})

	local serverPage = addPage("server")
	local serverList = make("ScrollingFrame", serverPage, {
		Name = "Players", BackgroundColor3 = Style.Ink, BackgroundTransparency = 0.28, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 148), LayoutOrder = 1, ScrollBarThickness = 4,
		ScrollBarImageColor3 = MUTED,
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	corner(serverList, 6)
	make("UIStroke", serverList, {Color = Style.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	make("UIPadding", serverList, {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
	})
	make("UIListLayout", serverList, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
	local serverUserId = make("TextBox", serverPage, {
		Name = "UserId", Text = "", PlaceholderText = "User id", ClearTextOnFocus = false, TextEditable = true,
		BackgroundColor3 = FIELD, BorderSizePixel = 0, TextColor3 = INK, PlaceholderColor3 = MUTED,
		Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, ClipsDescendants = true,
	})
	corner(serverUserId, 6)
	outlineField(serverUserId)
	pad(serverUserId, 10)
	local serverUserLocked = ""
	local function setServerUserId(text)
		serverUserLocked = text
		serverUserId.Text = text
	end
	serverUserId:GetPropertyChangedSignal("Text"):Connect(function()
		if serverUserId.Text ~= serverUserLocked then serverUserId.Text = serverUserLocked end
	end)
	local serverStats = make("TextBox", serverPage, {
		Name = "Stats", Text = "Click a player.", ClearTextOnFocus = false, TextEditable = true, TextWrapped = true,
		BackgroundColor3 = FIELD, BorderSizePixel = 0, TextColor3 = INK,
		Font = Enum.Font.GothamBold, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 3, ClipsDescendants = true,
	})
	corner(serverStats, 6)
	outlineField(serverStats)
	pad(serverStats, 10)
	local serverStatsLocked = serverStats.Text
	local function setServerStats(text)
		serverStatsLocked = text
		serverStats.Text = text
	end
	serverStats:GetPropertyChangedSignal("Text"):Connect(function()
		if serverStats.Text ~= serverStatsLocked then serverStats.Text = serverStatsLocked end
	end)
	local serverButtons = make("Frame", serverPage, {
		Name = "Actions", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 108), LayoutOrder = 4,
	})
	make("UIGridLayout", serverButtons, {
		CellSize = UDim2.new(0.5, -4, 0, 32), CellPadding = UDim2.fromOffset(8, 6),
		FillDirectionMaxCells = 2, SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local function gridButton(name, text, order)
		local button = Style.Button(serverButtons, text, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), TAB)
		button.Name = name
		button.TextSize = 14
		button.LayoutOrder = order
		return button
	end
	local bringButton = gridButton("Teleport", "Teleport", 1)
	local gotoButton = gridButton("TeleportTo", "Teleport to", 2)
	local spectateButton = gridButton("Spectate", "Spectate", 3)
	local speedButton = gridButton("Speed", "Grant speed", 4)
	local jumpButton = gridButton("Jump", "Grant jump", 5)

	local tabs = {}
	local refreshServer
	local function showPage(name)
		for pageName, page in pairs(pageList) do
			page.Visible = pageName == name
		end
		for tabName, button in pairs(tabs) do
			paintTab(button, tabName == name)
		end
		if name == "server" and refreshServer then refreshServer() end
	end
	for index, spec in ipairs({
		{"coins", "Coins"}, {"lookup", "Lookup"}, {"ban", "Ban"}, {"reset", "Reset"}, {"colors", "Colors"}, {"server", "Server"},
	}) do
		local button = Style.Button(tabRow, spec[2], UDim2.fromOffset(0, 0), UDim2.new(1 / 6, -5, 1, 0), index == 1 and TAB_ON or TAB)
		button.Name = spec[1]
		button.TextSize = 13
		button.LayoutOrder = index
		tabs[spec[1]] = button
		button.Activated:Connect(function() showPage(spec[1]) end)
	end
	showPage("coins")

	local open = false
	local function setStatus(text, ok)
		status.Text = text or ""
		if ok == true then status.TextColor3 = Color3.fromRGB(120, 210, 140)
		elseif ok == false then status.TextColor3 = Color3.fromRGB(255, 140, 140)
		else status.TextColor3 = MUTED end
	end

	local function send(action, data, quiet)
		if player:GetAttribute("Admin") ~= true then
			setStatus("Not allowed.", false)
			return
		end
		if not requestRemote then
			setStatus("Admin tools are still loading.", false)
			return
		end
		data.action = action
		if not quiet then setStatus("Working...", nil) end
		requestRemote:FireServer(data)
	end
	refreshServer = function()
		send("players", {}, true)
	end

	local selectedUserId
	local spectating
	local spectateAdded
	local function stopSpectate()
		spectating = nil
		if spectateAdded then
			spectateAdded:Disconnect()
			spectateAdded = nil
		end
		spectateButton.Text = "Spectate"
		local camera = workspace.CurrentCamera
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera and humanoid then camera.CameraSubject = humanoid end
	end
	local function follow(target)
		local camera = workspace.CurrentCamera
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if not camera or not humanoid or humanoid.Health <= 0 then return false end
		camera.CameraSubject = humanoid
		return true
	end
	local function renderPlayers(rows)
		for _, child in ipairs(serverList:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		local found = false
		for index, entry in ipairs(rows) do
			if entry.userId == selectedUserId then found = true end
			local row = Style.Button(serverList, "", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 36),
				entry.userId == selectedUserId and TAB_ON or Style.Slot)
			row.Name = "PlayerRow"
			row.LayoutOrder = index
			local face = make("ImageLabel", row, {
				Name = "Avatar", BackgroundColor3 = Color3.fromRGB(40, 52, 66), BorderSizePixel = 0,
				Image = headshot(entry.userId), ScaleType = Enum.ScaleType.Crop,
				Position = UDim2.fromOffset(5, 4), Size = UDim2.fromOffset(28, 28),
				ClipsDescendants = true,
			})
			make("UICorner", face, {CornerRadius = UDim.new(1, 0)})
			make("TextLabel", row, {
				BackgroundTransparency = 1, BorderSizePixel = 0,
				Text = playerLabel(entry), TextColor3 = INK, Font = Enum.Font.Gotham, TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -48, 1, 0),
			})
			row.Activated:Connect(function()
				selectedUserId = entry.userId
				setServerUserId(tostring(entry.userId))
				setServerStats("Loading...")
				for _, other in ipairs(serverList:GetChildren()) do
					if other:IsA("TextButton") then
						Style.Recolor(other, other == row and TAB_ON or Style.Slot)
						local stroke = other:FindFirstChildOfClass("UIStroke")
						if stroke then stroke.Color = other == row and Style.Accent or Style.Ink end
					end
				end
				if spectating and spectating.UserId ~= entry.userId then
					spectateButton.Text = "Spectate"
				end
				send("lookup", {user = tostring(entry.userId)})
			end)
		end
		if selectedUserId and not found then setServerStats("They left this server.") end
	end
	local function serverStatsText(profile)
		return table.concat({
			tostring(profile.displayName or "Player") .. " (@" .. tostring(profile.username or "Unknown") .. ")",
			profile.online and "In this server" or "Offline",
			"Coins  " .. tostring(profile.coins or 0) .. " held, " .. tostring(profile.coinsEarned or 0) .. " lifetime",
			"Kills  " .. tostring(profile.kills or 0) .. "    Played  " .. formatTime(profile.playedSeconds),
			"Speed rank " .. tostring(profile.speed or 0) .. "   Distance " .. tostring(profile.distance or 0),
			"Duration rank " .. tostring(profile.duration or 0) .. "   Resistance " .. tostring(profile.resistance or 0),
		}, "\n")
	end
	local function requireSelection()
		if type(selectedUserId) ~= "number" then
			setStatus("Click a player first.", false)
			return false
		end
		return true
	end

	give.Activated:Connect(function()
		send("grant", {user = coinUser.Text, amount = coinAmount.Text})
	end)
	loadPlayer.Activated:Connect(function()
		hideLookupFace()
		setResult("Loading...")
		send("lookup", {user = lookupUser.Text})
	end)
	banButton.Activated:Connect(function()
		send("ban", {user = banUser.Text, reason = banReason.Text})
	end)
	unbanButton.Activated:Connect(function()
		send("unban", {user = banUser.Text})
	end)
	resetCoins.Activated:Connect(function() send("reset", {user = resetUser.Text, kind = "coins"}) end)
	resetKills.Activated:Connect(function() send("reset", {user = resetUser.Text, kind = "kills"}) end)
	resetTime.Activated:Connect(function() send("reset", {user = resetUser.Text, kind = "time"}) end)
	resetRanks.Activated:Connect(function() send("reset", {user = resetUser.Text, kind = "upgrades"}) end)
	resetAll.Activated:Connect(function() send("reset", {user = resetUser.Text, kind = "all"}) end)
	applyColor.Activated:Connect(function()
		send("color", {user = colorUser.Text, target = selectedTarget, color = colorName.Text})
	end)
	bringButton.Activated:Connect(function()
		if requireSelection() then send("bring", {userId = selectedUserId}) end
	end)
	gotoButton.Activated:Connect(function()
		if requireSelection() then send("goto", {userId = selectedUserId}) end
	end)
	speedButton.Activated:Connect(function()
		if requireSelection() then send("boost", {userId = selectedUserId, kind = "speed"}) end
	end)
	jumpButton.Activated:Connect(function()
		if requireSelection() then send("boost", {userId = selectedUserId, kind = "jump"}) end
	end)
	spectateButton.Activated:Connect(function()
		if not requireSelection() then return end
		local target = Players:GetPlayerByUserId(selectedUserId)
		if spectating == target then
			stopSpectate()
			setStatus("Stopped spectating.", true)
			return
		end
		if not target or not follow(target) then
			setStatus("They have no character.", false)
			return
		end
		if spectateAdded then spectateAdded:Disconnect() end
		spectating = target
		spectateButton.Text = "Stop spectate"
		spectateAdded = target.CharacterAdded:Connect(function()
			task.defer(function()
				if spectating == target then follow(target) end
			end)
		end)
		setStatus("Spectating " .. target.Name .. ".", true)
	end)
	Players.PlayerRemoving:Connect(function(leaving)
		if spectating == leaving then
			stopSpectate()
			setStatus("They left.", false)
		end
		if serverPage.Visible then refreshServer() end
	end)
	Players.PlayerAdded:Connect(function()
		if serverPage.Visible then refreshServer() end
	end)

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		requestRemote = folder:WaitForChild("AdminRequest")
		resultRemote = folder:WaitForChild("AdminResult")
		resultRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then return end
			if player:GetAttribute("Admin") ~= true then return end
			setStatus(payload.message, payload.ok == true)
			if payload.action == "lookup" then
				if type(payload.profile) == "table" then
					showLookupFace(payload.profile)
					setResult(profileText(payload.profile))
					if serverPage.Visible and payload.profile.userId == selectedUserId then
						setServerUserId(tostring(payload.profile.userId))
						setServerStats(serverStatsText(payload.profile))
					end
				elseif payload.ok ~= true then
					hideLookupFace()
					setResult(payload.message or "Could not load that player.")
					if serverPage.Visible then
						setServerStats(payload.message or "Could not load that player.")
					end
				end
			elseif payload.action == "players" and type(payload.players) == "table" then
				renderPlayers(payload.players)
			end
		end)
	end)

	local api = {}
	function api.hide()
		open = false
		window.Visible = false
	end
	function api.show(visible)
		if visible and player:GetAttribute("Admin") ~= true then
			api.hide()
			return
		end
		open = visible == true
		window.Visible = open
		if open then
			showPage("coins")
			if onOpen then onOpen() end
		end
	end
	local applyFit = CrispFit.attach(window, scale)
	function api.fit()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		if viewport.X < 1 or viewport.Y < 1 then return end
		local fitted = math.min((viewport.X - 24) / 500, (viewport.Y - 24) / 560)
		if UserInputService.TouchEnabled then fitted *= 0.85 end
		applyFit(math.clamp(fitted, 0.45, 1))
	end
	api.window = window
	api.scale = scale
	close.Activated:Connect(function() api.hide() end)
	title.Text = "Admin"
	coinNote.Visible = true
	return api
end

return M

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
local Ui = require(script.Parent:WaitForChild("CollectionUi"))
local make, text, round = Ui.Make, Ui.Text, Ui.Round
local blue = Color3.fromRGB(65, 133, 244)
local ink = Color3.fromRGB(41, 57, 82)
local white = Color3.fromRGB(255, 255, 255)
local function tween(object, duration, props, style)
	local animation = TweenService:Create(object, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	animation:Play()
	return animation
end

local function icon(parent, item)
	local function piece(position, size, color, radius)
		local frame = make("Frame", parent, {Position = position, Size = size, BorderSizePixel = 0,
			BackgroundColor3 = color or item.Color})
		round(frame, radius or 8)
		if not color then Ui.Paint(frame, item) end
		return frame
	end
	if item.Kind == "Bomb" then
		local fuse = piece(UDim2.fromOffset(60, 7), UDim2.fromOffset(8, 25), ink, 4)
		fuse.Rotation = 22
		piece(UDim2.fromOffset(65, 5), UDim2.fromOffset(10, 10), Color3.fromRGB(255, 203, 68), 5)
		piece(UDim2.fromOffset(28, 27), UDim2.fromOffset(66, 66), nil, 40)
		piece(UDim2.fromOffset(40, 37), UDim2.fromOffset(15, 9), white, 5).BackgroundTransparency = 0.35
	elseif item.Kind == "Gun" then
		piece(UDim2.fromOffset(26, 45), UDim2.fromOffset(23, 46), nil, 6).Rotation = 14
		piece(UDim2.fromOffset(17, 25), UDim2.fromOffset(83, 31))
		piece(UDim2.fromOffset(91, 29), UDim2.fromOffset(14, 23), ink, 4)
		piece(UDim2.fromOffset(26, 30), UDim2.fromOffset(48, 6), white, 3).BackgroundTransparency = 0.55
	else
		for i = 0, 2 do
			local loop = piece(UDim2.fromOffset(30 + i * 6, 20 + i * 9), UDim2.fromOffset(56, 46), white, 24)
			loop.BackgroundTransparency = 1
			make("UIStroke", loop, {Thickness = 7, Color = item.Name == "Rainbow" and Color3.fromHSV(i / 3, 0.8, 1) or item.Color})
		end
	end
end

local RollUi = {}
function RollUi.Init()
	local player = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("RequestCosmeticRoll")
	local random = Random.new()
	local screen = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "CosmeticRollGui", ResetOnSpawn = false,
		DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
	local shade = make("Frame", screen, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 32, 56),
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, Active = true})
	local panel = make("Frame", shade, {Name = "RollWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(580, 628), BackgroundColor3 = Color3.fromRGB(245, 248, 255), BorderSizePixel = 0})
	round(panel, 24)
	make("UIStroke", panel, {Color = white, Thickness = 4})
	local scale = make("UIScale", panel, {Scale = 1})
	local header = make("Frame", panel, {Size = UDim2.new(1, 0, 0, 112), BackgroundColor3 = blue, BorderSizePixel = 0})
	round(header, 24)
	make("UIGradient", header, {Color = ColorSequence.new(blue, Color3.fromRGB(103, 175, 255)), Rotation = 18})
	text(header, "COLOR CLUB", UDim2.fromOffset(24, 15), UDim2.fromOffset(430, 36), 30, white)
	text(header, "GUN  +  ROPE  +  BOMB", UDim2.fromOffset(26, 55), UDim2.fromOffset(400, 22), 13, Color3.fromRGB(221, 239, 255))
	local collection = text(header, "", UDim2.fromOffset(26, 80), UDim2.fromOffset(400, 22), 14, white)
	local close = make("TextButton", panel, {Position = UDim2.new(1, -54, 0, 17), Size = UDim2.fromOffset(36, 36),
		Text = "X", TextSize = 18, Font = Enum.Font.GothamBold, TextColor3 = ink, BackgroundColor3 = white, BorderSizePixel = 0})
	round(close, 12)
	local balance = text(panel, "", UDim2.fromOffset(24, 124), UDim2.fromOffset(280, 26), 16)
	local oddsButton = make("TextButton", panel, {Position = UDim2.fromOffset(358, 120), Size = UDim2.fromOffset(198, 32),
		Text = "View items & odds", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = blue,
		BackgroundColor3 = Color3.fromRGB(224, 235, 255), BorderSizePixel = 0})
	round(oddsButton, 10)
	local hero = make("Frame", panel, {Position = UDim2.fromOffset(20, 164), Size = UDim2.fromOffset(540, 216),
		BackgroundColor3 = Color3.fromRGB(226, 235, 251), BorderSizePixel = 0, ClipsDescendants = true})
	round(hero, 18)
	make("UIGradient", hero, {Color = ColorSequence.new(Color3.fromRGB(232, 240, 255), Color3.fromRGB(212, 226, 252)), Rotation = 90})
	local strip = make("Frame", hero, {Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(5200, 166), BackgroundTransparency = 1})
	local pointer = text(hero, "▼", UDim2.new(0.5, -16, 0, 0), UDim2.fromOffset(32, 30), 27, blue)
	pointer.TextXAlignment, pointer.ZIndex = Enum.TextXAlignment.Center, 5
	local focus = make("Frame", hero, {Position = UDim2.new(0.5, -71, 0, 26), Size = UDim2.fromOffset(142, 174),
		BackgroundTransparency = 1, ZIndex = 4})
	round(focus, 16)
	local focusStroke = make("UIStroke", focus, {Thickness = 3, Color = blue})
	local headline = text(panel, "Find your next favorite!", UDim2.fromOffset(24, 391), UDim2.fromOffset(532, 30), 23)
	headline.TextXAlignment = Enum.TextXAlignment.Center
	local detail = text(panel, "One roll. Every category. A little surprise.", UDim2.fromOffset(24, 426), UDim2.fromOffset(532, 36), 14, Color3.fromRGB(104, 121, 145))
	detail.TextXAlignment, detail.TextWrapped = Enum.TextXAlignment.Center, true
	local rollButton = make("TextButton", panel, {Position = UDim2.fromOffset(100, 474), Size = UDim2.fromOffset(380, 58),
		BackgroundColor3 = Color3.fromRGB(66, 192, 132), BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 23,
		TextColor3 = white, Text = "ROLL  •  100 COINS"})
	round(rollButton, 18)
	make("UIStroke", rollButton, {Color = Color3.fromRGB(42, 148, 100), Thickness = 2})
	local footer = text(panel, "Duplicates give coins back!", UDim2.fromOffset(24, 544), UDim2.fromOffset(532, 20), 13, Color3.fromRGB(104, 121, 145))
	footer.TextXAlignment = Enum.TextXAlignment.Center
	local refunds = text(panel, "Common 10  •  Uncommon 25  •  Rare 50\nEpic 75  •  Legendary 100", UDim2.fromOffset(24, 568), UDim2.fromOffset(532, 40), 12, Color3.fromRGB(104, 121, 145))
	refunds.TextXAlignment = Enum.TextXAlignment.Center
	local oddsPanel = make("Frame", panel, {Position = UDim2.fromOffset(20, 164), Size = UDim2.fromOffset(540, 298),
		BackgroundColor3 = Color3.fromRGB(245, 248, 255), BorderSizePixel = 0, Visible = false, ZIndex = 10})
	local oddsScroll = make("ScrollingFrame", oddsPanel, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y})
	make("UIListLayout", oddsScroll, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
	local tiers, odds = Catalog.Odds()
	local order = 0
	local explanation = text(oddsScroll, "Highest rarity checked first. Empty tiers are skipped.\nEach item in the winning tier has an equal chance.", UDim2.new(), UDim2.new(1, -12, 0, 42), 12)
	explanation.TextWrapped = true
	for _, rarity in ipairs(Catalog.Rarities) do
		order += 1
		local pool = Catalog.Pools[rarity.Name]
		local heading = rarity.Name == "Common" and "COMMON  •  Fallback" or string.format("%s  •  %g%% check", string.upper(rarity.Name), rarity.Chance * 100)
		heading ..= #pool == 0 and "  •  No items yet" or string.format("  •  %.4f%% overall", tiers[rarity.Name] * 100)
		local row = text(oddsScroll, heading, UDim2.new(), UDim2.new(1, -12, 0, 26), 13)
		row.LayoutOrder = order
		for _, item in ipairs(pool) do
			order += 1
			local rowFrame = make("Frame", oddsScroll, {Size = UDim2.new(1, -12, 0, 34), BackgroundColor3 = white, BorderSizePixel = 0, LayoutOrder = order})
			round(rowFrame, 8)
			local swatch = make("Frame", rowFrame, {Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0})
			round(swatch, 6) Ui.Paint(swatch, item)
			text(rowFrame, item.Kind .. " / " .. item.Name, UDim2.fromOffset(38, 0), UDim2.new(1, -150, 1, 0), 13)
			local chance = text(rowFrame, string.format("%.4f%%", odds[item.Id] * 100), UDim2.new(1, -100, 0, 0), UDim2.fromOffset(90, 34), 13)
			chance.TextXAlignment = Enum.TextXAlignment.Right
		end
	end

	local function card(item, index)
		local rarity = Catalog.Rarity(item.Rarity)
		local frame = make("Frame", strip, {Position = UDim2.fromOffset((index - 1) * 146, 0), Size = UDim2.fromOffset(132, 166),
			BackgroundColor3 = white, BorderSizePixel = 0})
		round(frame, 14)
		local category = text(frame, string.upper(item.Kind), UDim2.fromOffset(8, 7), UDim2.fromOffset(116, 18), 10, Color3.fromRGB(112, 131, 156))
		category.TextXAlignment = Enum.TextXAlignment.Center
		local art = make("Frame", frame, {Position = UDim2.fromOffset(5, 23), Size = UDim2.fromOffset(122, 100), BackgroundTransparency = 1})
		icon(art, item)
		local name = text(frame, item.Name, UDim2.fromOffset(4, 120), UDim2.fromOffset(124, 22), 15)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local tag = text(frame, string.upper(item.Rarity), UDim2.fromOffset(4, 145), UDim2.fromOffset(124, 15), 9, rarity.Color)
		tag.TextXAlignment = Enum.TextXAlignment.Center
		return frame
	end
	local function preview()
		strip:ClearAllChildren()
		for i = 1, 8 do card(Catalog.Roll(random), i) end
		strip.Position = UDim2.fromOffset(-88, 30)
	end
	preview()
	local busy, waiting, activeZone, dismissed, availableAt = false, false, nil, false, 0
	local pendingRequest
	local function show(visible)
		if shade.Visible == visible then return end
		shade.Visible = visible
		if visible then
			panel.Position = UDim2.fromScale(0.5, 0.54)
			tween(panel, 0.25, {Position = UDim2.fromScale(0.5, 0.5)}, Enum.EasingStyle.Back)
		end
	end
	close.Activated:Connect(function() dismissed = true show(false) end)
	oddsButton.Activated:Connect(function()
		if busy then return end
		oddsPanel.Visible = not oddsPanel.Visible
		oddsButton.Text = oddsPanel.Visible and "Back to rolling" or "View items & odds"
	end)
	local function celebrate(color)
		for i = 1, 24 do
			local confetti = make("Frame", hero, {Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(7, 12),
				BackgroundColor3 = i % 2 == 0 and color or Color3.fromHSV(random:NextNumber(), 0.5, 1), BorderSizePixel = 0, ZIndex = 7})
			tween(confetti, 0.9, {Position = UDim2.fromScale(random:NextNumber(), random:NextNumber()), Rotation = random:NextInteger(-240, 240), BackgroundTransparency = 1})
			task.delay(1, function() confetti:Destroy() end)
		end
	end
	rollButton.Activated:Connect(function()
		if busy or not activeZone or os.clock() < availableAt or player:GetAttribute("CosmeticRollAllowed") ~= true then return end
		if player:GetAttribute("CollectionLoaded") ~= true then return end
		busy, waiting = true, true
		availableAt = os.clock() + Catalog.Cooldown
		oddsPanel.Visible = false
		oddsButton.Text = "View items & odds"
		headline.Text, detail.Text = "Picking a little surprise...", "Getting your roll ready"
		focusStroke.Color = blue
		pendingRequest = pendingRequest or HttpService:GenerateGUID(false)
		local ok, result = pcall(function() return remote:InvokeServer(activeZone, pendingRequest) end)
		waiting = false
		if not ok or type(result) ~= "table" or not result.ok then
			headline.Text = "Let's try that again"
			detail.Text = ok and type(result) == "table" and result.message or "Connection interrupted. Retry to check your roll."
			busy = false
			return
		end
		pendingRequest = nil
		local item = Catalog.ById[result.itemId]
		if not item then busy = false detail.Text = "Collection updated. Please rejoin to refresh the catalog." return end
		strip:ClearAllChildren()
		local winnerIndex = 28
		for i = 1, 31 do card(i == winnerIndex and item or Catalog.Roll(random), i) end
		strip.Position = UDim2.fromOffset(0, 30)
		headline.Text, detail.Text = "Here we go!", "Which color will join your collection?"
		local landing = 270 - ((winnerIndex - 1) * 146 + 66)
		local animation = tween(strip, 3.7, {Position = UDim2.fromOffset(landing, 30)}, Enum.EasingStyle.Quint)
		animation.Completed:Wait()
		local rarity = Catalog.Rarity(item.Rarity)
		focusStroke.Color = rarity.Color
		headline.Text = item.Name .. " " .. item.Kind
		detail.Text = result.duplicate and string.format("%s duplicate  •  +%d coins refunded", item.Rarity, result.refund)
			or item.Rarity .. "  •  NEW! Find it in your inventory."
		celebrate(rarity.Color)
		busy = false
	end)

	-- Client-owned billboards show this player's progress, never another player's.
	local stations = {}
	local function addStation(part)
		if stations[part] or not Catalog.IsStationPart(part) then return end
		local bounds, size = part:FindFirstAncestor(Catalog.ModelName):GetBoundingBox()
		local height = (math.abs(bounds.RightVector.Y) * size.X + math.abs(bounds.UpVector.Y) * size.Y
			+ math.abs(bounds.LookVector.Y) * size.Z) * 0.5
		local aboveModel = bounds.Position + Vector3.new(0, height + 2, 0) - part.Position
		local billboard = make("BillboardGui", screen, {Name = "CollectionProgress", Adornee = part,
			Size = UDim2.fromOffset(260, 84), StudsOffsetWorldSpace = aboveModel,
			MaxDistance = Catalog.BillboardDistance, AlwaysOnTop = true})
		local background = make("Frame", billboard, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = blue, BorderSizePixel = 0, BackgroundTransparency = 0.08})
		round(background, 18)
		make("UIStroke", background, {Color = white, Thickness = 2})
		local title = text(background, "COLOR CLUB  •  100 COINS", UDim2.fromOffset(8, 9), UDim2.fromOffset(244, 23), 15, white)
		title.TextXAlignment = Enum.TextXAlignment.Center
		local owned = text(background, Ui.OwnedText(player), UDim2.fromOffset(8, 35), UDim2.fromOffset(244, 24), 18, white)
		owned.TextXAlignment = Enum.TextXAlignment.Center
		local hint = text(background, "Walk closer to roll", UDim2.fromOffset(8, 61), UDim2.fromOffset(244, 16), 10, white)
		hint.TextXAlignment = Enum.TextXAlignment.Center
		stations[part] = {Gui = billboard, Label = owned}
	end
	for _, part in ipairs(workspace:GetDescendants()) do addStation(part) end
	workspace.DescendantAdded:Connect(addStation)
	workspace.DescendantRemoving:Connect(function(part)
		local station = stations[part]
		if station then station.Gui:Destroy() stations[part] = nil end
	end)
	local function refreshCollection()
		collection.Text = Ui.OwnedText(player)
		for _, station in pairs(stations) do station.Label.Text = collection.Text end
	end
	refreshCollection()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "CollectionLoaded" then refreshCollection() end
	end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if camera then scale.Scale = math.min(1, (camera.ViewportSize.X - 24) / 580, (camera.ViewportSize.Y - 64) / 628) end
		if waiting then strip.Position = UDim2.fromOffset(-88 - (os.clock() * 230) % 730, 30) end
		elapsed += dt
		if elapsed < 0.15 then return end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local nearest, distance = nil, Catalog.OpenDistance
		if root and humanoid and humanoid.Health > 0 then
			for part in pairs(stations) do
				if Catalog.IsStationPart(part) then
					local current = Catalog.Distance(part, root.Position)
					if current <= distance then nearest, distance = part, current end
				end
			end
		end
		activeZone = nearest
		if not activeZone then dismissed = false if not busy then show(false) end
		elseif not dismissed then show(true) end
		local coins = player:GetAttribute("Coins") or 0
		balance.Text = string.format("YOUR COINS  •  %d", coins)
		local allowed = player:GetAttribute("CosmeticRollAllowed") == true
		local loaded = player:GetAttribute("CollectionLoaded") == true
		local cooldown = math.max(0, math.ceil(availableAt - os.clock()))
		local enabled = not busy and allowed and loaded and cooldown == 0 and activeZone ~= nil
		rollButton.AutoButtonColor = enabled
		rollButton.BackgroundColor3 = enabled and Color3.fromRGB(66, 192, 132) or Color3.fromRGB(153, 172, 193)
		rollButton.Text = busy and "ROLLING..." or not loaded and "LOADING COLLECTION..." or not allowed and "ROLLS UNAVAILABLE"
			or cooldown > 0 and ("READY IN " .. cooldown .. "s") or "ROLL  •  100 COINS"
		footer.Text = allowed and "Duplicates give coins back!" or (player:GetAttribute("CosmeticRollPolicy") or "Checking roll availability...")
	end)
end
return RollUi

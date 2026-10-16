local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
local Ui = require(script.Parent:WaitForChild("CollectionUi"))
local make, text, round = Ui.Make, Ui.Text, Ui.Round
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local CrispFit = require(script.Parent:WaitForChild("CrispFit"))
local ScreenFocus = require(script.Parent:WaitForChild("CosmeticScreenFocus"))
local PlaySound = require(script.Parent:WaitForChild("PlaySound"))
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local accent, ink, white = Style.Accent, Style.Ink, Style.Text
text = Style.Label
local function withCommas(amount)
	local value = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
	while true do
		local formatted, count = string.gsub(value, "^(%d+)(%d%d%d)", "%1,%2")
		value = formatted
		if count == 0 then return value end
	end
end
local function tween(object, duration, props, style)
	local animation = TweenService:Create(object, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	animation:Play()
	return animation
end

local icon = Style.Icon

local RollUi = {}
function RollUi.Init()
	local player = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("RequestCosmeticRoll")
	local random = Random.new()
	local screen = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "CosmeticRollGui", ResetOnSpawn = false,
		DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
	local focusScreens = ScreenFocus.new(player:WaitForChild("PlayerGui"), screen)
	local shade = make("Frame", screen, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, Visible = false, Active = false})
	local panel = make("Frame", shade, {Name = "RollWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, 548)})
	Style.Surface(panel, Style.Panel, 8)
	local scale = make("UIScale", panel, {Scale = 1})
	local header = make("Frame", panel, {Size = UDim2.new(1, 0, 0, 94)})
	Style.Surface(header, Style.Header, 8)
	text(header, "COSMETICS", UDim2.fromOffset(24, 12), UDim2.fromOffset(360, 36), 30)
	text(header, "GUN  /  ROPE  /  BOMB", UDim2.fromOffset(26, 55), UDim2.fromOffset(340, 22), 13, Style.Muted)
	local luckStatus = text(header, "", UDim2.fromOffset(380, 55), UDim2.fromOffset(180, 22), 13, Style.Muted)
	luckStatus.TextXAlignment = Enum.TextXAlignment.Right
	local close = Style.Button(panel, "X", UDim2.new(1, -58, 0, 12), UDim2.fromOffset(42, 36), Style.Danger)
	local balance = text(panel, "", UDim2.fromOffset(24, 106), UDim2.fromOffset(300, 26), 16, Color3.fromRGB(255, 209, 115))
	local oddsButton = Style.Button(panel, "Items & odds", UDim2.fromOffset(458, 104), UDim2.fromOffset(198, 32), Style.ButtonColor)
	oddsButton.TextSize = 14
	local hero = make("Frame", panel, {Position = UDim2.fromOffset(20, 150), Size = UDim2.fromOffset(640, 216), ClipsDescendants = true})
	Style.Surface(hero, Style.Slot, 6)
	local strip = make("Frame", hero, {Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(5200, 166), BackgroundTransparency = 1})
	local pointer = text(hero, "▼", UDim2.new(0.5, -16, 0, 0), UDim2.fromOffset(32, 30), 27, accent)
	pointer.TextXAlignment, pointer.ZIndex = Enum.TextXAlignment.Center, 5
	local focus = make("Frame", hero, {Position = UDim2.new(0.5, -71, 0, 26), Size = UDim2.fromOffset(142, 174),
		BackgroundTransparency = 1, ZIndex = 4})
	round(focus, 5)
	local focusStroke = make("UIStroke", focus, {Thickness = 3, Color = accent})
	local headline = text(panel, "Roll a cosmetic", UDim2.fromOffset(24, 378), UDim2.fromOffset(632, 30), 23)
	headline.TextXAlignment = Enum.TextXAlignment.Center
	local detail = text(panel, "", UDim2.fromOffset(24, 414), UDim2.fromOffset(632, 36), 15, Style.Muted)
	detail.TextXAlignment, detail.TextWrapped = Enum.TextXAlignment.Center, true
	local rollButton = Style.Button(panel, "ROLL  /  100 COINS", UDim2.fromOffset(150, 466), UDim2.fromOffset(380, 52), Style.Action)
	rollButton.TextSize = 23
	local footer = text(panel, "", UDim2.fromOffset(24, 525), UDim2.fromOffset(632, 18), 12, Style.Muted)
	footer.TextXAlignment = Enum.TextXAlignment.Center
	local oddsPanel = make("Frame", panel, {Position = UDim2.fromOffset(20, 150), Size = UDim2.fromOffset(640, 300), Visible = false, ZIndex = 10})
	Style.Surface(oddsPanel, Style.Slot, 6)
	local oddsScroll = make("ScrollingFrame", oddsPanel, {Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 1, -12), BackgroundTransparency = 1,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, BorderSizePixel = 0,
		ScrollBarImageColor3 = Style.Muted, ScrollingDirection = Enum.ScrollingDirection.Y})
	make("UIListLayout", oddsScroll, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
	local tierLabels, oddsLabels = {}, {}
	local tiers, odds = Catalog.Odds(Catalog.LuckMultiplier(player))
	local order = 0
	for _, rarity in ipairs(Catalog.Rarities) do
		local pool = Catalog.Pools[rarity.Name]
		if #pool == 0 then continue end
		order += 1
		local heading = string.format("%s  /  %.4f%%", string.upper(rarity.Name), tiers[rarity.Name] * 100)
		local row = text(oddsScroll, heading, UDim2.new(), UDim2.new(1, -12, 0, 26), 13, rarity.Color)
		row.LayoutOrder = order
		tierLabels[rarity.Name] = row
		for _, item in ipairs(pool) do
			order += 1
			local rowFrame = make("Frame", oddsScroll, {Size = UDim2.new(1, -12, 0, 34), BackgroundColor3 = Style.ButtonColor, BackgroundTransparency = 0.55, BorderSizePixel = 0, LayoutOrder = order})
			round(rowFrame, 4)
			local swatch = make("Frame", rowFrame, {Position = UDim2.fromOffset(7, 4), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, BorderSizePixel = 0})
			icon(swatch, item)
			text(rowFrame, item.Kind .. " / " .. item.Name, UDim2.fromOffset(38, 0), UDim2.new(1, -150, 1, 0), 13)
			local chance = text(rowFrame, string.format("%.4f%%", odds[item.Id] * 100), UDim2.new(1, -100, 0, 0), UDim2.fromOffset(90, 34), 13)
			chance.TextXAlignment = Enum.TextXAlignment.Right
			oddsLabels[item.Id] = chance
		end
	end
	local function refreshLuck()
		local multiplier = Catalog.LuckMultiplier(player)
		local active = multiplier > 1
		luckStatus.Text = active and "2x Luck active" or "2x Luck not active"
		luckStatus.TextColor3 = Style.HeaderText or (active and Style.Accent or Style.Danger)
		local currentTiers, currentOdds = Catalog.Odds(multiplier)
		for _, rarity in ipairs(Catalog.Rarities) do
			local label = tierLabels[rarity.Name]
			if label then label.Text = string.format("%s  /  %.4f%%", string.upper(rarity.Name), currentTiers[rarity.Name] * 100) end
		end
		for itemId, label in pairs(oddsLabels) do
			label.Text = string.format("%.4f%%", (currentOdds[itemId] or 0) * 100)
		end
	end
	refreshLuck()
	player:GetAttributeChangedSignal("TestPass_2xLuck"):Connect(refreshLuck)

	local function card(item, index)
		local rarity = Catalog.Rarity(item.Rarity)
		local frame = make("Frame", strip, {Position = UDim2.fromOffset((index - 1) * 146, 0), Size = UDim2.fromOffset(132, 166),
			BackgroundColor3 = Style.Slot, BorderSizePixel = 0})
		Style.Surface(frame, Style.ButtonColor, 5)
		local category = text(frame, string.upper(item.Kind), UDim2.fromOffset(8, 7), UDim2.fromOffset(116, 18), 10, Style.Muted)
		category.TextXAlignment = Enum.TextXAlignment.Center
		local art = make("Frame", frame, {Name = "ItemIcon", Position = UDim2.fromOffset(5, 23),
			Size = UDim2.fromOffset(122, 100), BackgroundTransparency = 1, BorderSizePixel = 0})
		icon(art, item)
		local name = text(frame, item.Name, UDim2.fromOffset(4, 120), UDim2.fromOffset(124, 22), 15)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local tag = text(frame, string.upper(item.Rarity), UDim2.fromOffset(4, 145), UDim2.fromOffset(124, 15), 9, rarity.Color)
		tag.TextXAlignment = Enum.TextXAlignment.Center
		return frame
	end
	local idle, resumePreviewAt, idleOffset = true, 0, 0
	local idleCards, previewBag = {}, {}
	local function nextPreviewItem()
		if #previewBag == 0 then
			for _, item in ipairs(Catalog.Items) do if not item.Starter and not item.Vip then table.insert(previewBag, item) end end
			for i = #previewBag, 2, -1 do
				local j = random:NextInteger(1, i)
				previewBag[i], previewBag[j] = previewBag[j], previewBag[i]
			end
		end
		return table.remove(previewBag)
	end
	local function preview()
		idle, idleOffset = true, 0
		table.clear(idleCards)
		strip:ClearAllChildren()
		for i = 1, 7 do idleCards[i] = card(nextPreviewItem(), i) end
		strip.Position = UDim2.fromOffset(0, 30)
		pointer.Visible, focus.Visible = false, false
	end
	preview()
	local busy, waiting, activeZone, dismissed, availableAt = false, false, nil, false, 0
	local pendingRequest
	local spinning, lastPassed = false, 0
	local function tick()
		local sounds = ReplicatedStorage:FindFirstChild("Sounds")
		local source = sounds and sounds:FindFirstChild("Tick", true)
		if not source or not source:IsA("Sound") then return end
		local sound = source:Clone()
		sound.Looped = false
		sound.TimePosition = 0
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Once(function() sound:Destroy() end)
		Debris:AddItem(sound, math.max(5, sound.TimeLength + 1))
	end
	local function updateTicks()
		-- Count centers crossing the pointer, even if a slow frame crosses two.
		-- Crisp fit stores the strip in screen pixels, so convert back to the 146px card step.
		local applied = scale:GetAttribute("CrispFactor")
		local designX = strip.Position.X.Offset
		if type(applied) == "number" and applied > 0 then designX = designX / applied end
		local passed = math.floor((320 - designX - 66) / 146)
		if shade.Visible then for _ = lastPassed + 1, passed do tick() end end
		lastPassed = passed
	end
	local function show(visible)
		if shade.Visible == visible then return end
		shade.Visible = visible
		player:SetAttribute("CosmeticRollOpen", visible)
		focusScreens(visible)
		if visible then
			if not busy then
				preview()
				headline.Text, detail.Text = "Roll a cosmetic", ""
			end
			panel.Position = UDim2.fromScale(0.5, 0.54)
			tween(panel, 0.25, {Position = UDim2.fromScale(0.5, 0.5)}, Enum.EasingStyle.Back)
		end
	end
	close.Activated:Connect(function() dismissed = true show(false) end)
	oddsButton.Activated:Connect(function()
		if busy then return end
		oddsPanel.Visible = not oddsPanel.Visible
		oddsButton.Text = oddsPanel.Visible and "Back to rolling" or "Items & odds"
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
		if not idle then preview() end
		availableAt = os.clock() + Catalog.Cooldown
		oddsPanel.Visible = false
		oddsButton.Text = "Items & odds"
		headline.Text, detail.Text = "Rolling...", ""
		focusStroke.Color = accent
		pendingRequest = pendingRequest or HttpService:GenerateGUID(false)
		local ok, result = pcall(function() return remote:InvokeServer(activeZone, pendingRequest) end)
		waiting = false
		if not ok or type(result) ~= "table" or not result.ok then
			headline.Text = "Couldn't roll"
			detail.Text = ok and type(result) == "table" and result.message or "Connection interrupted. Retry to check your roll."
			busy = false
			return
		end
		pendingRequest = nil
		local item = Catalog.ById[result.itemId]
		if not item then busy = false detail.Text = "Collection updated. Please rejoin to refresh the catalog." return end
		idle = false
		table.clear(idleCards)
		strip:ClearAllChildren()
		pointer.Visible, focus.Visible = true, true
		local winnerIndex = 28
		for i = 1, 31 do card(i == winnerIndex and item or Catalog.Roll(random), i) end
		strip.Position = UDim2.fromOffset(0, 30)
		lastPassed = math.floor((320 - 66) / 146)
		spinning = true
		headline.Text, detail.Text = "Rolling...", ""
		local landing = 320 - ((winnerIndex - 1) * 146 + 66)
		local animation = tween(strip, 3.7, {Position = UDim2.fromOffset(landing, 30)}, Enum.EasingStyle.Quint)
		animation.Completed:Wait()
		updateTicks()
		spinning = false
		local rarity = Catalog.Rarity(item.Rarity)
		focusStroke.Color = rarity.Color
		headline.Text = item.Name .. " " .. item.Kind
		detail.Text = result.duplicate and string.format("%s  /  Added to your stack  /  x%d", item.Rarity, result.copies or Catalog.Copies(player, item.Kind, item.Name))
			or item.Rarity .. "  /  NEW"
		if not result.duplicate then PlaySound(SoundService, "Reward") end
		local rareOrBetter = item.Rarity == "Rare" or item.Rarity == "Epic" or item.Rarity == "Legendary"
		if rareOrBetter or not result.duplicate then celebrate(rarity.Color) end
		resumePreviewAt = os.clock() + 4
		busy = false
	end)

	-- Client-owned billboards show this player's progress, never another player's.
	local stations = {}
	local function addStation(part)
		if stations[part] or not Catalog.IsStationPart(part) then return end
		local bounds, size = part:FindFirstAncestor(Catalog.ModelName):GetBoundingBox()
		local height = (math.abs(bounds.RightVector.Y) * size.X + math.abs(bounds.UpVector.Y) * size.Y
			+ math.abs(bounds.LookVector.Y) * size.Z) * 0.5
		local aboveModel = bounds.Position + Vector3.new(0, height + 12, 0) - part.Position
		local billboard = make("BillboardGui", screen, {Name = "CollectionProgress", Adornee = part,
			Size = UDim2.fromOffset(260, 68), StudsOffsetWorldSpace = aboveModel,
			MaxDistance = Catalog.BillboardDistance, AlwaysOnTop = true, LightInfluence = 0})
		local title = text(billboard, "COSMETICS", UDim2.fromOffset(8, 2), UDim2.fromOffset(244, 23), 16, accent)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.Font = Enum.Font.GothamBlack
		title.TextStrokeTransparency = 0.12
		local owned = text(billboard, Ui.OwnedText(player), UDim2.fromOffset(8, 28), UDim2.fromOffset(244, 29), 20, white)
		owned.TextXAlignment = Enum.TextXAlignment.Center
		owned.Font = Enum.Font.GothamBlack
		owned.TextStrokeTransparency = 0.12
		make("UIGradient", owned, {Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, accent),
		})})
		stations[part] = {Gui = billboard, Label = owned}
	end
	for _, part in ipairs(workspace:GetDescendants()) do addStation(part) end
	workspace.DescendantAdded:Connect(addStation)
	workspace.DescendantRemoving:Connect(function(part)
		local station = stations[part]
		if station then station.Gui:Destroy() stations[part] = nil end
	end)
	local function refreshCollection()
		local ownedText = Ui.OwnedText(player)
		for _, station in pairs(stations) do station.Label.Text = ownedText end
	end
	refreshCollection()
	player.AttributeChanged:Connect(function(key)
		if string.sub(key, 1, 6) == "Owned_" or key == "CollectionLoaded" or key == "TestPass_VIP" then refreshCollection() end
	end)
	local elapsed = 0
	local applyFit = CrispFit.attach(panel, scale)
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if camera then applyFit(math.max(0.01, math.min(1, (camera.ViewportSize.X - 24) / 680, (camera.ViewportSize.Y - 64) / 548))) end
		if spinning then updateTicks() end
		if shade.Visible and not oddsPanel.Visible then
			if not busy and not idle and os.clock() >= resumePreviewAt then
				preview()
				headline.Text, detail.Text = "Roll a cosmetic", ""
			end
			if idle then
				idleOffset -= 32 * math.min(dt, 0.25)
				while idleOffset <= -146 do
					idleOffset += 146
					table.remove(idleCards, 1):Destroy()
					table.insert(idleCards, card(nextPreviewItem(), 7))
					for i, frame in ipairs(idleCards) do frame.Position = UDim2.fromOffset((i - 1) * 146, 0) end
				end
				strip.Position = UDim2.fromOffset(idleOffset, 30)
			end
		end
		elapsed += dt
		if elapsed < 0.15 then return end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local nearest = nil
		if root and humanoid and humanoid.Health > 0 then
			for part in pairs(stations) do
				if Catalog.IsStationPart(part) and Catalog.Inside(part, root.Position) then
					nearest = part
					break
				end
			end
		end
		activeZone = nearest
		if not activeZone then dismissed = false if not busy then show(false) end
		elseif not dismissed then show(true) end
		local coins = player:GetAttribute("Coins") or 0
		balance.Text = "YOUR COINS  •  " .. withCommas(coins)
		local allowed = player:GetAttribute("CosmeticRollAllowed") == true
		local loaded = player:GetAttribute("CollectionLoaded") == true
		local cooldown = math.max(0, math.ceil(availableAt - os.clock()))
		local enabled = not busy and allowed and loaded and cooldown == 0 and activeZone ~= nil
		rollButton.AutoButtonColor = enabled
		rollButton.TextTransparency = enabled and 0 or 0.35
		rollButton.Text = busy and "ROLLING..." or not loaded and "LOADING COLLECTION..." or not allowed and "ROLLS UNAVAILABLE"
			or cooldown > 0 and ("READY IN " .. cooldown .. "s") or "ROLL  •  100 COINS"
		footer.Text = allowed and "" or (player:GetAttribute("CosmeticRollPolicy") or "Checking roll availability...")
	end)
end
return RollUi

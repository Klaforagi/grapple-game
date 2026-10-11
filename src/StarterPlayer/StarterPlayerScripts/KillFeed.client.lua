-- Newest kills sit under the older ones at the top-right, left of the settings
-- button. Each line is one row: a headshot, then that player's name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local KillCredit = require(ReplicatedStorage.Modules:WaitForChild("KillCredit"))
local Palettes = require(ReplicatedStorage:WaitForChild("ItemColors"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))

local HOLD = 6.5
local FADE = 0.35
local GAP = 8
local MAX_ROWS = 6
local FONT = Enum.Font.GothamBold
local TEXT_SIZE = 16
local ROW = 28
local AVATAR = 22
local NAME_GAP = 5
local RIGHT_INSET = 80
local TEXT_COLOR = Color3.fromRGB(232, 240, 247)
local DARK_STROKE = Color3.fromRGB(27, 42, 53)
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.Name = "KillFeed"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.DisplayOrder = 25
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local feed = Instance.new("Frame")
feed.Name = "Feed"
feed.AnchorPoint = Vector2.new(1, 0)
feed.Position = UDim2.new(1, -RIGHT_INSET, 0, 12)
feed.Size = UDim2.new(1, -(RIGHT_INSET + 16), 0, 280)
feed.BackgroundTransparency = 1
feed.BorderSizePixel = 0
feed.Active = false
feed.ClipsDescendants = false
feed.Parent = screen

local rows = {}
local rowState = setmetatable({}, {__mode = "k"})
local thumbs = {}
local gradients = {}
local layoutQueued = false

local function state(row)
	local record = rowState[row]
	if record then return record end
	record = {}
	rowState[row] = record
	return record
end

local function rowHeight(row)
	local height = row.AbsoluteSize.Y
	if height < 1 then return state(row).expectedHeight or ROW end
	return height
end

local function layout()
	local y = 0
	for _, row in ipairs(rows) do
		local target = UDim2.new(1, 0, 0, y)
		local record = state(row)
		if record.placed then
			TweenService:Create(row, SLIDE, {Position = target}):Play()
		else
			row.Position = target
			record.placed = true
		end
		y += rowHeight(row) + GAP
	end
end

local function queueLayout()
	layout()
	if layoutQueued then return end
	layoutQueued = true
	task.spawn(function()
		RunService.Heartbeat:Wait()
		layoutQueued = false
		layout()
	end)
end

local function fade(row, disappearing, info)
	local transparency = disappearing and 1 or 0
	for _, child in ipairs(row:GetDescendants()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, info, {TextTransparency = transparency}):Play()
		elseif child:IsA("ImageLabel") then
			TweenService:Create(child, info, {ImageTransparency = transparency}):Play()
		elseif child:IsA("UIStroke") then
			TweenService:Create(child, info, {Transparency = transparency}):Play()
		end
	end
end

local function removeRow(row)
	local index = table.find(rows, row)
	if index then table.remove(rows, index) end
	if row.Parent then row:Destroy() end
	queueLayout()
end

local function dismiss(row)
	local record = state(row)
	if record.dismissed then return end
	record.dismissed = true
	fade(row, true, FADE_OUT)
	task.delay(FADE, function()
		removeRow(row)
	end)
end

local function clean(text)
	if type(text) ~= "string" then return "Player" end
	text = text:gsub("[%c]", "")
	if text == "" then return "Player" end
	return text
end

local function availableWidth()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize.X or 1280
	if viewport < 200 then viewport = 1280 end
	return math.max(180, viewport - RIGHT_INSET - 16)
end

local function measure(text, textSize)
	return TextService:GetTextSize(text, textSize, FONT, Vector2.new(8000, ROW)).X
end

local function outline(parent)
	local stroke = Instance.new("UIStroke")
	stroke.Color = DARK_STROKE
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = parent
end

local function paintCycling(label, color)
	label.TextColor3 = color
end

local function applyRopeColor(label, colorName)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if colorName == "Rainbow" or colorName == "Gold" then
		gradients[#gradients + 1] = {label = label, kind = colorName}
		local phase = (workspace:GetServerTimeNow() * Palettes.CycleSpeed) % 1
		paintCycling(label, colorName == "Gold" and Palettes.GoldAt(phase) or Palettes.RainbowAt(phase))
		return
	end
	local color = type(colorName) == "string" and Palettes.Rope[colorName]
	if typeof(color) ~= "Color3" then return end
	label.TextColor3 = color
	local luminance = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722
	if stroke and luminance < 0.35 then stroke.Color = Color3.new(1, 1, 1) end
end

local function wordLabel(text, color, textSize)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, ROW)
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.TextTransparency = 1
	label.Active = false
	outline(label)
	return label
end

local function portrait(userId, avatarSize)
	local photo = Instance.new("ImageLabel")
	photo.Name = "Portrait"
	photo.BackgroundTransparency = 1
	photo.BorderSizePixel = 0
	photo.Size = UDim2.fromOffset(avatarSize, avatarSize)
	photo.ScaleType = Enum.ScaleType.Fit
	photo.ImageTransparency = 1
	photo.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = photo
	if type(userId) ~= "number" then
		photo.Visible = false
		return photo
	end
	local cached = thumbs[userId]
	if type(cached) == "string" then
		photo.Image = cached
		return photo
	end
	task.spawn(function()
		local content
		for _ = 1, 3 do
			local ok, image, ready = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and ready and type(image) == "string" and image ~= "" then
				content = image
				break
			end
			task.wait(0.4)
		end
		if not content then
			if photo.Parent then photo.Visible = false end
			return
		end
		thumbs[userId] = content
		if photo.Parent then photo.Image = content end
	end)
	return photo
end

local function playerChip(userId, name, ropeName, textSize, avatarSize)
	local group = Instance.new("Frame")
	group.Name = "Player"
	group.BackgroundTransparency = 1
	group.AutomaticSize = Enum.AutomaticSize.X
	group.Size = UDim2.fromOffset(0, ROW)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, NAME_GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = group
	local photo = portrait(userId, avatarSize)
	photo.LayoutOrder = 1
	photo.Parent = group
	local label = wordLabel(name, TEXT_COLOR, textSize)
	applyRopeColor(label, ropeName)
	label.LayoutOrder = 2
	label.Parent = group
	return group
end

local function splitLine(line)
	local killerAt, killerEnd = string.find(line, "{Killer}", 1, true)
	local victimAt, victimEnd = string.find(line, "{Victim}", 1, true)
	if not killerAt or not victimAt or killerAt > victimAt then return nil end
	return string.sub(line, killerEnd + 1, victimAt - 1), string.sub(line, victimEnd + 1)
end

local function fitted(killerName, victimName, middle, tail, killerId, victimId)
	local textSize = TEXT_SIZE
	local avatarSize = AVATAR
	local function width(size, avatar)
		local total = measure(killerName, size) + measure(middle, size) + measure(victimName, size) + measure(tail, size)
		if type(killerId) == "number" then total += avatar + NAME_GAP end
		if type(victimId) == "number" then total += avatar + NAME_GAP end
		return total
	end
	local limit = availableWidth()
	while textSize > 12 and width(textSize, avatarSize) > limit do
		textSize -= 1
		avatarSize = math.max(16, textSize + 6)
	end
	return textSize, avatarSize
end

local function push(killerName, victimName, cause, lineIndex, killerId, victimId, solo, killerRope, victimRope)
	if type(killerName) ~= "string" or type(victimName) ~= "string" or type(cause) ~= "string" then return end
	killerName = clean(killerName)
	victimName = clean(victimName)
	local middle, tail
	if solo == true then
		local template = KillCredit.SoloLines[cause]
		if type(template) ~= "string" then return end
		local nameAt, nameEnd = string.find(template, "{Player}", 1, true)
		if not nameAt then return end
		middle = string.sub(template, 1, nameAt - 1)
		tail = string.sub(template, nameEnd + 1)
		killerName, killerId = "", nil
		killerRope = victimRope
	else
		if type(lineIndex) ~= "number" then return end
		local lines = KillCredit.Lines[cause]
		local line = lines and lines[lineIndex]
		if type(line) ~= "string" then return end
		middle, tail = splitLine(line)
		if not middle then
			middle, tail = KillCredit.Plain(line, killerName, victimName), ""
			killerName, victimName = "", ""
		end
	end

	local textSize, avatarSize = fitted(killerName, victimName, middle, tail, killerId, victimId)
	local row = Instance.new("Frame")
	row.Name = "Kill"
	row.AnchorPoint = Vector2.new(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, ROW)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Active = false
	state(row).expectedHeight = ROW
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	local order = 1
	local function add(child)
		child.LayoutOrder = order
		order += 1
		child.Parent = row
	end
	if killerName ~= "" then add(playerChip(killerId, killerName, killerRope, textSize, avatarSize)) end
	if middle ~= "" then add(wordLabel(middle, TEXT_COLOR, textSize)) end
	if victimName ~= "" then add(playerChip(victimId, victimName, victimRope, textSize, avatarSize)) end
	if tail ~= "" then add(wordLabel(tail, TEXT_COLOR, textSize)) end
	row.Parent = feed

	while #rows >= MAX_ROWS do
		local oldest = table.remove(rows, 1)
		state(oldest).dismissed = true
		oldest:Destroy()
	end
	rows[#rows + 1] = row
	fade(row, false, FADE_INFO)
	queueLayout()
	task.delay(HOLD, function()
		if row.Parent and not state(row).dismissed then dismiss(row) end
	end)
end

RunService.RenderStepped:Connect(function()
	-- One flat color for the whole name, stepped through the rope palette.
	local phase = (workspace:GetServerTimeNow() * Palettes.CycleSpeed) % 1
	local write = 1
	for index = 1, #gradients do
		local entry = gradients[index]
		if entry.label.Parent then
			local color = entry.kind == "Gold" and Palettes.GoldAt(phase) or Palettes.RainbowAt(phase)
			paintCycling(entry.label, color)
			gradients[write] = entry
			write += 1
		end
	end
	for index = write, #gradients do
		gradients[index] = nil
	end
end)

Remotes.KillFeed.OnClientEvent:Connect(push)

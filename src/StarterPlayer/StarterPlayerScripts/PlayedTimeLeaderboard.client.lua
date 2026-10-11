local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local boardFolder = ReplicatedStorage:WaitForChild("PlayedTimeBoard")

local GOLD = Color3.fromRGB(255, 198, 92)
local INK = Color3.fromRGB(232, 240, 247)
local MUTED = Color3.fromRGB(154, 170, 186)
local PAGE_SIZE = 100

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	seconds -= days * 86400
	local hours = math.floor(seconds / 3600)
	seconds -= hours * 3600
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	if days > 0 then return string.format("%dd %dh", days, hours) end
	if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
	if minutes > 0 then return string.format("%dm %02ds", minutes, secs) end
	return secs .. "s"
end

local function make(class, parent, props)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local RANK_COLOR = {
	Color3.fromRGB(255, 198, 92),
	Color3.fromRGB(186, 198, 210),
	Color3.fromRGB(206, 150, 96),
}

local function findBoard(model)
	local named, marked, largest, area
	local function consider(part)
		if not part:IsA("BasePart") then return end
		local key = string.lower(part.Name):gsub("[%s_]", "")
		if key == "screen" or key == "display" or key == "board" or key == "surface" then
			named = named or part
		end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("SurfaceGui") or child:IsA("Decal") or child:IsA("Texture") then
				marked = marked or part
			end
		end
		local size = part.Size
		local score = 0
		if size then
			score = math.max((size.X or 0) * (size.Y or 0), (size.X or 0) * (size.Z or 0), (size.Y or 0) * (size.Z or 0))
		end
		if not largest or score > area then largest, area = part, score end
	end
	if model:IsA("BasePart") then consider(model) end
	for _, descendant in ipairs(model:GetDescendants()) do consider(descendant) end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return named or marked or model.PrimaryPart
	end
	return named or marked or largest
end

local function boardFace(part)
	local attr = part:GetAttribute("LeaderboardFace")
	if attr == nil and part.Parent then attr = part.Parent:GetAttribute("LeaderboardFace") end
	if typeof(attr) == "EnumItem" then return attr end
	if type(attr) == "string" and Enum.NormalId[attr] then return Enum.NormalId[attr] end
	for _, child in ipairs(part:GetChildren()) do
		if (child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceGui")) and child.Face then
			return child.Face
		end
	end
	return Enum.NormalId.Front
end

-- One SurfaceGui per player. A part in the world is shared, so the "you" card
-- has to be drawn locally or everyone would see the same pinned row.
local boards = {}
local mounted = {}

local function corner(parent, radius)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
end

local function buildRow(parent)
	local row = make("Frame", parent, {
		Name = "Row", BackgroundColor3 = Color3.fromRGB(20, 28, 40),
		BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 96),
	})
	corner(row, 12)
	make("TextLabel", row, {
		Name = "Rank", BackgroundTransparency = 1, Position = UDim2.new(0, 4, 0, 0),
		Size = UDim2.new(0, 88, 1, 0), Font = Enum.Font.GothamBold, TextSize = 34,
		TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, Text = "#",
	})
	local avatar = make("ImageLabel", row, {
		Name = "Avatar", BackgroundColor3 = Color3.fromRGB(8, 12, 18), BorderSizePixel = 0,
		Position = UDim2.new(0, 96, 0.5, -34), Size = UDim2.fromOffset(68, 68),
		Image = "", ScaleType = Enum.ScaleType.Fit,
	})
	corner(avatar, 34)
	make("TextLabel", row, {
		Name = "PlayerName", BackgroundTransparency = 1, Position = UDim2.new(0, 176, 0, 12),
		Size = UDim2.new(1, -352, 0, 40), Font = Enum.Font.GothamBold, TextSize = 32,
		TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
	})
	make("TextLabel", row, {
		Name = "Username", BackgroundTransparency = 1, Position = UDim2.new(0, 176, 0, 52),
		Size = UDim2.new(1, -352, 0, 32), Font = Enum.Font.GothamMedium, TextSize = 22,
		TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
	})
	make("TextLabel", row, {
		Name = "Time", BackgroundTransparency = 1, Position = UDim2.new(1, -160, 0, 0),
		Size = UDim2.fromOffset(148, 96), Font = Enum.Font.GothamBold, TextSize = 32,
		TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center, Text = "",
	})
	return row
end

local function recordFrom(gui)
	local root = gui:FindFirstChild("Board")
	local list = root and root:FindFirstChild("List")
	local you = root and root:FindFirstChild("You")
	if not list or not you then return end
	return {
		list = list, empty = list:FindFirstChild("Empty"), you = you,
		youRank = you:FindFirstChild("Rank"), youName = you:FindFirstChild("PlayerName"),
		youTime = you:FindFirstChild("Time"), rows = {},
	}
end

local function createGui(part)
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("SurfaceGui") and child.Name == "PlayedTime" and child.Adornee == part then
			local existing = recordFrom(child)
			if existing then return existing end
			child:Destroy()
		end
	end
	local gui = make("SurfaceGui", playerGui, {
		Name = "PlayedTime", Adornee = part, Face = boardFace(part),
		LightInfluence = 0, Brightness = 1.15, MaxDistance = 120, ClipsDescendants = true,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 42,
		ZOffset = 0.04, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local root = make("Frame", gui, {
		Name = "Board", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 24, 36),
		BorderSizePixel = 0, ClipsDescendants = true,
	})
	corner(root, 12)
	make("UIStroke", root, {Color = GOLD, Thickness = 1.5, Transparency = 0.45})
	make("UIGradient", root, {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 42, 62)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 30)),
		}),
	})
	local header = make("Frame", root, {
		Name = "Header", BackgroundTransparency = 1, Position = UDim2.new(0.04, 0, 0.025, 0),
		Size = UDim2.new(0.92, 0, 0.12, 0),
	})
	make("TextLabel", header, {
		Name = "Title", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.62, 0),
		Font = Enum.Font.GothamBold, Text = "PLAYED TIME", TextScaled = true,
		TextColor3 = Color3.fromRGB(246, 240, 224), TextXAlignment = Enum.TextXAlignment.Left,
	})
	make("TextLabel", header, {
		Name = "Subtitle", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.64, 0),
		Size = UDim2.new(1, 0, 0.32, 0), Font = Enum.Font.GothamMedium, Text = "ALL-TIME RANKING",
		TextScaled = true, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left,
	})
	make("Frame", root, {
		Name = "Rule", BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Position = UDim2.new(0.04, 0, 0.15, 0), Size = UDim2.new(0.18, 0, 0, 2),
	})
	-- Ends above the pinned card. The card is not a child of this scroller.
	local list = make("ScrollingFrame", root, {
		Name = "List", BackgroundColor3 = Color3.fromRGB(8, 12, 20), BackgroundTransparency = 0.35,
		BorderSizePixel = 0, Position = UDim2.new(0.04, 0, 0.17, 0), Size = UDim2.new(0.92, 0, 0.68, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5, ScrollBarImageColor3 = GOLD, ScrollingDirection = Enum.ScrollingDirection.Y,
		ClipsDescendants = true,
	})
	corner(list, 10)
	make("UIPadding", list, {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
	})
	make("UIListLayout", list, {
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
	})
	local empty = make("TextLabel", list, {
		Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48),
		Font = Enum.Font.GothamMedium, TextSize = 24, TextColor3 = MUTED,
		Text = "No times yet", TextXAlignment = Enum.TextXAlignment.Center,
	})
	local you = make("Frame", root, {
		Name = "You", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.04, 0, 0.99, 0),
		Size = UDim2.new(0.92, 0, 0.11, 0), BackgroundColor3 = Color3.fromRGB(36, 78, 128),
		BorderSizePixel = 0, ZIndex = 3,
	})
	corner(you, 10)
	make("UIStroke", you, {Color = GOLD, Thickness = 1.4, Transparency = 0.1})
	local youRank = make("TextLabel", you, {
		Name = "Rank", BackgroundTransparency = 1, Position = UDim2.new(0.04, 0, 0.16, 0),
		Size = UDim2.new(0.16, 0, 0.68, 0), Font = Enum.Font.GothamBold, Text = "—",
		TextScaled = true, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local avatar = make("ImageLabel", you, {
		Name = "Avatar", BackgroundColor3 = Color3.fromRGB(8, 12, 18), BorderSizePixel = 0,
		Position = UDim2.new(0.22, 0, 0.14, 0), Size = UDim2.new(0.12, 0, 0.72, 0),
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=48&h=48",
		ScaleType = Enum.ScaleType.Fit,
	})
	corner(avatar, 16)
	local youName = make("TextLabel", you, {
		Name = "PlayerName", BackgroundTransparency = 1, Position = UDim2.new(0.36, 0, 0.14, 0),
		Size = UDim2.new(0.34, 0, 0.72, 0), Font = Enum.Font.GothamBold, TextScaled = true,
		TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
	})
	local youTime = make("TextLabel", you, {
		Name = "Time", BackgroundTransparency = 1, Position = UDim2.new(0.7, 0, 0.14, 0),
		Size = UDim2.new(0.26, 0, 0.72, 0), Font = Enum.Font.GothamBold, TextScaled = true,
		TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, Text = "0s",
	})
	return {list = list, empty = empty, you = you, youRank = youRank, youName = youName, youTime = youTime, rows = {}}
end

local function readEntries()
	local entries = {}
	for _, child in ipairs(boardFolder:GetChildren()) do
		if child:IsA("IntValue") then table.insert(entries, child) end
	end
	table.sort(entries, function(a, b)
		return (tonumber(string.match(a.Name, "%d+")) or 0) < (tonumber(string.match(b.Name, "%d+")) or 0)
	end)
	return entries
end

local function rankLabel(entries)
	for index, entry in ipairs(entries) do
		if entry:GetAttribute("UserId") == player.UserId then return "#" .. index end
	end
	if #entries >= PAGE_SIZE then return PAGE_SIZE .. "+" end
	return "—"
end

local function rowColor(rank)
	if rank == 1 then return Color3.fromRGB(48, 40, 22) end
	if rank == 2 then return Color3.fromRGB(34, 40, 48) end
	if rank == 3 then return Color3.fromRGB(46, 34, 26) end
	if rank % 2 == 0 then return Color3.fromRGB(24, 34, 48) end
	return Color3.fromRGB(18, 26, 38)
end

local function render()
	local entries = readEntries()
	for _, board in ipairs(boards) do
		local seen = {}
		for index, entry in ipairs(entries) do
			local id = entry:GetAttribute("UserId")
			seen[id] = true
			local row = board.rows[id]
			if not row or not row.Parent then
				row = buildRow(board.list)
				board.rows[id] = row
			end
			row.LayoutOrder = index
			row.BackgroundColor3 = rowColor(index)
			local rank = row:FindFirstChild("Rank")
			rank.Text = "#" .. index
			rank.TextColor3 = RANK_COLOR[index] or INK
			local nickname = entry:GetAttribute("DisplayName")
			local username = entry:GetAttribute("Username")
			if type(nickname) ~= "string" or nickname == "" then nickname = username or "Player" end
			if type(username) ~= "string" or username == "" then username = nickname end
			row:FindFirstChild("PlayerName").Text = nickname
			row:FindFirstChild("Username").Text = "@" .. username
			row:FindFirstChild("Time").Text = formatTime(entry.Value)
			row:FindFirstChild("Avatar").Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150"
		end
		for id, row in pairs(board.rows) do
			if not seen[id] and row.Parent then row:Destroy() end
			if not seen[id] then board.rows[id] = nil end
		end
		board.empty.Visible = #entries == 0
		board.youRank.Text = rankLabel(entries)
	end
end

local function updateYou()
	local name = player.DisplayName
	if type(name) ~= "string" or name == "" then name = player.Name end
	local timeText = formatTime(player:GetAttribute("PlayedSeconds"))
	for _, board in ipairs(boards) do
		board.youName.Text = name
		board.youTime.Text = timeText
	end
end

local function mount(model)
	if mounted[model] or not model then return end
	if model.Name ~= "LeaderboardPlayedTime" then return end
	if not model:IsA("Model") and not model:IsA("BasePart") then return end
	local part = findBoard(model)
	if not part then return end
	mounted[model] = true
	-- A SurfaceGui authored on the shared part would draw the same pixels for every
	-- player. The live board lives in PlayerGui, so the placeholder has to step aside.
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") then child.Enabled = false end
	end
	local record = createGui(part)
	if record.list then table.insert(boards, record) end
	render()
	updateYou()
end

boardFolder:GetAttributeChangedSignal("Version"):Connect(render)
player:GetAttributeChangedSignal("PlayedSeconds"):Connect(updateYou)

local function consider(instance)
	if instance.Name == "LeaderboardPlayedTime" then
		mount(instance)
		return
	end
	local ancestor = instance.FindFirstAncestor and instance:FindFirstAncestor("LeaderboardPlayedTime")
	if ancestor then mount(ancestor) end
end

Workspace.DescendantAdded:Connect(consider)
for _, instance in ipairs(Workspace:GetDescendants()) do consider(instance) end

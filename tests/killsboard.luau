return function(serverSource, clientSource)
	local function expect(actual, expected, label)
		assert(actual == expected, label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
	end

	local function signal()
		local callbacks = {}
		local self = {}
		function self:Connect(callback)
			table.insert(callbacks, callback)
			return {Disconnect = function() end}
		end
		function self:Emit(...)
			for index = 1, #callbacks do callbacks[index](...) end
		end
		return self
	end

	local function makeWorld()
		local objects, methods = {}, {}
		local function isDescendant(object, ancestor)
			local parent = object.Parent
			while parent do
				if parent == ancestor then return true end
				parent = parent.Parent
			end
			return false
		end
		local function new(class, name, parent)
			local object = setmetatable({
				ClassName = class, Name = name or class, Parent = parent, Visible = true, Enabled = true,
				attributes = {}, DescendantAdded = signal(), ChildAdded = signal(),
			}, {
				__index = function(object, key)
					if key == "Parent" then return rawget(object, "Parent") end
					local method = methods[key]
					if method ~= nil then return method end
					return methods.FindFirstChild(object, key)
				end,
				__newindex = function(object, key, value)
					rawset(object, key, value)
					if key ~= "Parent" or not value then return end
					local ancestor = value
					while ancestor do
						if ancestor.DescendantAdded then ancestor.DescendantAdded:Emit(object) end
						ancestor = ancestor.Parent
					end
				end,
			})
			table.insert(objects, object)
			return object
		end
		function methods:IsA(class)
			return self.ClassName == class or class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")
		end
		function methods:GetChildren()
			local result = {}
			for _, object in ipairs(objects) do if object.Parent == self then table.insert(result, object) end end
			return result
		end
		function methods:GetDescendants()
			local result = {}
			for _, object in ipairs(objects) do if isDescendant(object, self) then table.insert(result, object) end end
			return result
		end
		function methods:FindFirstChild(name)
			for _, object in ipairs(self:GetChildren()) do if object.Name == name then return object end end
		end
		function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
		function methods:FindFirstAncestor(name)
			local parent = self.Parent
			while parent do
				if parent.Name == name then return parent end
				parent = parent.Parent
			end
		end
		function methods:GetAttribute(key) return self.attributes[key] end
		function methods:GetAttributeChangedSignal(key)
			self.attributeSignals = self.attributeSignals or {}
			self.attributeSignals[key] = self.attributeSignals[key] or signal()
			return self.attributeSignals[key]
		end
		function methods:SetAttribute(key, value)
			local previous = self.attributes[key]
			self.attributes[key] = value
			local listeners = self.attributeSignals and self.attributeSignals[key]
			if previous ~= value and listeners then listeners:Emit() end
		end
		function methods:Destroy()
			for _, child in ipairs(self:GetChildren()) do child:Destroy() end
			rawset(self, "Parent", nil)
		end
		return new
	end

	local function publishedOf(board)
		local list = {}
		for _, child in ipairs(board:GetChildren()) do
			if child:IsA("IntValue") then table.insert(list, child) end
		end
		table.sort(list, function(a, b) return a.Name < b.Name end)
		return list
	end

	local function byId(list, userId)
		for _, child in ipairs(list) do
			if child:GetAttribute("UserId") == userId then return child end
		end
	end

	local function scenario(source, broken)
		local now, session, orderedWrites = 0, 0, 0
		local records, ranks, warnings = {}, {}, {}
		local storeName, orderedName
		local api = {}
		local new = makeWorld()
		local replicated = new("Folder", "ReplicatedStorage")
		local modules = new("Folder", "Modules", replicated)
		new("ModuleScript", "KillCredit", modules)
		new("ModuleScript", "GrappleRemotes", modules)
		local longName = string.rep("A", 30)
		local player = {Name = "KillerUser", DisplayName = longName, UserId = 77, attributes = {}}
		function player:SetAttribute(key, value) self.attributes[key] = value end
		function player:GetAttribute(key) return self.attributes[key] end
		local players = {}
		player.Parent = players
		function players:GetPlayers() return {player} end
		function players:GetPlayerByUserId(id) if id == player.UserId then return player end end
		function players:GetNameFromUserIdAsync(id)
			if type(id) ~= "number" or id < 0 then error("no username") end
			if id == 5 then return "Ace" end
			return "User" .. id
		end
		local dataStores = {
			GetDataStore = function(_, name)
				storeName = name
				return {
					GetAsync = function(_, key) return records[key] end,
					UpdateAsync = function(_, key, transform)
						local updated = transform(records[key])
						if updated ~= nil then records[key] = updated end
						return updated
					end,
				}
			end,
			GetOrderedDataStore = function(_, name)
				orderedName = name
				return {
					GetSortedAsync = function(_, ascending, pageSize)
						local page = {}
						for key, value in pairs(ranks) do table.insert(page, {key = key, value = value}) end
						table.sort(page, function(a, b)
							if a.value == b.value then return tostring(a.key) < tostring(b.key) end
							if ascending then return a.value < b.value end
							return a.value > b.value
						end)
						while #page > pageSize do table.remove(page) end
						return {GetCurrentPage = function() return page end}
					end,
					UpdateAsync = function(_, key, transform)
						local updated = transform(ranks[key])
						if updated ~= nil then ranks[key] = updated orderedWrites += 1 end
						return ranks[key]
					end,
				}
			end,
		}
		if broken then
			dataStores = {
				GetDataStore = function() error("DataStore unavailable") end,
				GetOrderedDataStore = function() error("DataStore unavailable") end,
			}
		end
		local services = {
			Players = setmetatable(players, {__index = {PlayerAdded = {Connect = function() end},
				PlayerRemoving = {Connect = function() end}}}),
			DataStoreService = dataStores,
			HttpService = {GenerateGUID = function() session += 1 return "kill-" .. tostring(session) end},
			RunService = {Heartbeat = {Connect = function(_, fn) api.beat = fn end}},
			ReplicatedStorage = replicated,
		}
		local env = setmetatable({
			warn = function(message) table.insert(warnings, tostring(message)) end,
			game = {GetService = function(_, name) return assert(services[name], name) end,
				BindToClose = function(_, fn) api.close = fn end},
			Instance = {new = new},
			os = {clock = function() return now end, time = function() return 1000 + now end},
			task = {spawn = function(fn, ...) fn(...) end, wait = function() error("unexpected retry") end},
			require = function(module)
				if module.Name == "KillCredit" then
					return {SetListener = function(fn) api.onKill = fn end}
				end
				if module.Name == "GrappleRemotes" then
					return {KillFeed = {FireAllClients = function() end}}
				end
				error("Unexpected require " .. tostring(module.Name))
			end,
		}, {__index = getfenv()})
		local function boot()
			local fn = assert(loadstring(source))
			setfenv(fn, env)
			fn()
		end
		boot()
		local function board() return replicated:FindFirstChild("KillsBoard") end
		return {
			player = player, records = records, ranks = ranks, warnings = warnings,
			beat = function() api.beat() end,
			award = function(count)
				api.onKill({killerId = player.UserId, cause = "Lava", count = count, show = false}, player)
			end,
			setTime = function(t) now = t end,
			published = function() return publishedOf(board()) end,
			writes = function() return orderedWrites end,
			names = function() return storeName, orderedName end,
		}
	end

	local live = scenario(serverSource)
	local storeName, orderedName = live.names()
	expect(storeName, "GrappleKills_v1", "kills store")
	expect(orderedName, "GrappleKillsRank_v1", "kills ranking")
	live.beat()
	expect(#live.published(), 0, "empty kills board")
	assert(live.player.attributes.Kills == nil, "kills attribute set before a kill")
	live.ranks["5"], live.ranks["3"], live.ranks["9"], live.ranks["-8"] = 10, 4, 4, 8
	live.setTime(60)
	live.beat()
	local page = live.published()
	expect(#page, 4, "saved ranking count")
	expect(page[1]:GetAttribute("UserId"), 5, "first place")
	expect(page[1].Value, 10, "first kills")
	expect(page[1]:GetAttribute("DisplayName"), "Ace", "offline name")
	expect(page[1]:GetAttribute("Username"), "Ace", "offline username")
	expect(page[2]:GetAttribute("UserId"), -8, "second place")
	expect(page[2]:GetAttribute("DisplayName"), "Player", "studio username")
	expect(page[2]:GetAttribute("Username"), "Player", "missing username")
	expect(page[3]:GetAttribute("UserId"), 3, "tied user")
	expect(page[4]:GetAttribute("UserId"), 9, "later tied user")
	live.award(false)
	expect(live.player.attributes.Kills, nil, "uncounted death changed kills")
	assert(live.records["player_77"] == nil, "uncounted death was stored")
	live.award(true)
	expect(live.player.attributes.Kills, 1, "first kill attribute")
	expect(live.records["player_77"].kills, 1, "first kill save")
	expect(live.records["player_77"].name, string.rep("A", 30), "stored display name")
	expect(live.records["player_77"].username, "KillerUser", "stored username")
	expect(live.writes(), 0, "kill wrote the ordered rank early")
	assert(byId(live.published(), 77) == nil, "board refreshed on the kill")
	live.award(true)
	expect(live.player.attributes.Kills, 2, "second kill attribute")
	expect(live.records["player_77"].kills, 2, "second kill save")
	expect(live.writes(), 0, "second kill wrote the ordered rank early")
	live.setTime(120)
	live.beat()
	expect(live.ranks["77"], 2, "ordered rank")
	expect(live.ranks["5"], 10, "higher rank overwritten")
	expect(live.writes(), 1, "ordered writes")
	local row = byId(live.published(), 77)
	expect(row.Value, 2, "board after the minute")
	expect(row:GetAttribute("DisplayName"), string.rep("A", 24), "truncated name")
	expect(row:GetAttribute("Username"), "KillerUser", "live username")
	expect(#live.warnings, 0, "unexpected warning")
	for index = 1, 110 do live.ranks[tostring(2000 + index)] = 1000 + index end
	live.setTime(180)
	live.beat()
	page = live.published()
	expect(#page, 100, "ranking cap")
	expect(page[1]:GetAttribute("UserId"), 2110, "capped first place")
	expect(page[1].Value, 1110, "capped first kills")
	assert(byId(page, 77) == nil, "full board kept a lower total")

	local studio = scenario(serverSource, true)
	studio.beat()
	expect(#studio.published(), 0, "studio empty board")
	studio.award(true)
	expect(studio.player.attributes.Kills, 1, "studio kill attribute")
	expect(#studio.published(), 0, "studio board refreshed on the kill")
	studio.setTime(60)
	studio.beat()
	page = studio.published()
	expect(#page, 1, "studio personal row")
	expect(page[1].Value, 1, "studio kills")
	expect(page[1]:GetAttribute("DisplayName"), string.rep("A", 24), "studio name")
	expect(page[1]:GetAttribute("Username"), "KillerUser", "studio username")
	assert(studio.records["player_77"] == nil, "studio save wrote without a store")
	studio.award(true)
	expect(#studio.warnings, 1, "studio warning")

	local new = makeWorld()
	local workspace = new("Workspace", "Workspace")
	local replicated = new("Folder", "ReplicatedStorage")
	local board = new("Folder", "KillsBoard", replicated)
	local player = new("Player", "KillerUser")
	player.UserId = 77
	player.DisplayName = "Killer"
	local playerGui = new("PlayerGui", "PlayerGui", player)
	local played = new("Model", "LeaderboardPlayedTime", workspace)
	new("Part", "Screen", played)
	local model = new("Model", "LeaderboardKills", workspace)
	local trim = new("Part", "Trim", model)
	trim.Size = {X = 100, Y = 80, Z = 4}
	model.PrimaryPart = trim
	local decoy = new("SurfaceGui", "Decoy", trim)
	local screen = new("Part", "Screen", model)
	screen.Size = {X = 2, Y = 2, Z = 0.2}
	local decal = new("Decal", "Face", screen)
	decal.Face = "Back"
	local oldGui = new("SurfaceGui", "OldBoard", screen)
	local services = {
		Players = {LocalPlayer = player}, Workspace = workspace, ReplicatedStorage = replicated,
	}
	local enum = setmetatable({}, {__index = function(_, group)
		return setmetatable({}, {__index = function(_, name) return group .. "." .. name end})
	end})
	local function udim2(xScale, xOffset, yScale, yOffset)
		return {X = {Scale = xScale, Offset = xOffset}, Y = {Scale = yScale, Offset = yOffset}}
	end
	local env = setmetatable({
		game = {GetService = function(_, name) return assert(services[name], name) end},
		Instance = {new = new},
		Color3 = {fromRGB = function() return {} end},
		ColorSequence = {new = function(value) return value end},
		ColorSequenceKeypoint = {new = function() return {} end},
		UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end},
		UDim2 = {new = udim2, fromScale = function(x, y) return udim2(x, 0, y, 0) end,
			fromOffset = function(x, y) return udim2(0, x, 0, y) end},
		Vector2 = {new = function(x, y) return {X = x, Y = y} end},
		Enum = enum,
	}, {__index = getfenv()})
	local client = assert(loadstring(clientSource))
	setfenv(client, env)
	client()
	local function pinned(root)
		local list, you = root:FindFirstChild("List"), root:FindFirstChild("You")
		assert(list and list:IsA("ScrollingFrame"), "ranking should scroll")
		assert(you and you:IsA("Frame"), "personal card missing")
		assert(you.Parent == root and list.Parent == root, "personal card is inside the scroller")
		expect(you.AnchorPoint and you.AnchorPoint.Y, 1, "personal card anchor")
		local listBottom = list.Position.Y.Scale + list.Size.Y.Scale
		local youTop = you.Position.Y.Scale - you.Size.Y.Scale
		assert(youTop - listBottom > 0.01, "personal card overlaps the scrolling list")
		assert(you:FindFirstChild("Rank") and you:FindFirstChild("PlayerName") and you:FindFirstChild("Kills"),
			"personal card labels")
		return list, you
	end
	local gui = playerGui:FindFirstChild("Kills")
	assert(gui and gui:IsA("SurfaceGui") and gui.Parent == playerGui, "board gui parent")
	assert(gui.Adornee == screen, "named screen lost to the larger trim")
	expect(gui.Face, "Back", "board face")
	expect(gui.ResetOnSpawn, false, "board respawn")
	expect(gui.LightInfluence, 0, "board lighting")
	expect(gui.PixelsPerStud, 42, "board scale")
	expect(oldGui.Enabled, false, "placeholder surface")
	expect(decoy.Enabled, true, "unrelated surface")
	assert(screen:FindFirstChild("Kills") == nil, "shared surface was parented to the part")
	local root = gui:FindFirstChild("Board")
	expect(root:FindFirstChild("Header"):FindFirstChild("Title").Text, "KILLS", "title")
	expect(root:FindFirstChild("Header"):FindFirstChild("Subtitle").Text, "ALL-TIME RANKING", "subtitle")
	local list, you = pinned(root)
	local unranked = you:FindFirstChild("Rank").Text
	assert(you:FindFirstChild("Tag") == nil, "personal card has a caption")
	assert(you.Size.Y.Scale < 0.14 and you.Size.Y.Scale > 0.08, "personal card should be slightly shorter")
	assert(you.Position.Y.Scale >= 0.98, "personal card should sit on the bottom")
	expect(list:FindFirstChild("Empty").Text, "No kills yet", "empty label")
	expect(list:FindFirstChild("Empty").Visible, true, "empty state")
	expect(you:FindFirstChild("PlayerName").Text, "Killer", "personal name")
	expect(you:FindFirstChild("Kills").Text, "0", "starting personal kills")
	expect(you:FindFirstChild("Rank").Text, unranked, "unranked label")
	player:SetAttribute("Kills", 12)
	expect(you:FindFirstChild("Kills").Text, "12", "personal kills")
	local function rowFor(parent, userId)
		local needle = "id=" .. userId .. "&"
		for _, child in ipairs(parent:GetChildren()) do
			local avatar = child:FindFirstChild("Avatar")
			if avatar and string.find(avatar.Image, needle, 1, true) then return child end
		end
	end
	local function rowCount()
		local count = 0
		for _, child in ipairs(list:GetChildren()) do if child.Name == "Row" then count += 1 end end
		return count
	end
	local ace = new("IntValue", "Rank01", board)
	ace.Value = 20
	ace:SetAttribute("UserId", 5)
	ace:SetAttribute("DisplayName", "Ace")
	ace:SetAttribute("Username", "AceUser")
	local selfEntry = new("IntValue", "Rank02", board)
	selfEntry.Value = 4
	selfEntry:SetAttribute("UserId", 77)
	selfEntry:SetAttribute("DisplayName", "Listed")
	selfEntry:SetAttribute("Username", "KillerUser")
	board:SetAttribute("Version", 1)
	local listed = rowFor(list, 77)
	assert(listed and listed.Parent == list and listed ~= you, "local player missing from the scrolling list")
	expect(listed:FindFirstChild("Rank").Text, "#2", "list rank")
	expect(listed:FindFirstChild("PlayerName").Text, "Listed", "list name")
	expect(listed:FindFirstChild("Username").Text, "@KillerUser", "list username")
	expect(listed.Size.Y.Offset >= 90, true, "list row height")
	expect(listed:FindFirstChild("PlayerName").TextSize >= 30, true, "list name size")
	expect(listed:FindFirstChild("Kills").TextSize >= 30, true, "list kills size")
	expect(listed:FindFirstChild("Kills").Text, "4", "list kills")
	expect(you:FindFirstChild("Rank").Text, "#2", "personal rank")
	expect(you:FindFirstChild("PlayerName").Text, "Killer", "personal name while listed")
	expect(you:FindFirstChild("Kills").Text, "12", "personal kills while listed")
	expect(list:FindFirstChild("Empty").Visible, false, "empty hidden")
	expect(you.Parent, root, "listing the player reparented their card")
	for _, child in ipairs(board:GetChildren()) do if child:IsA("IntValue") then child:Destroy() end end
	for index = 1, 100 do
		local value = new("IntValue", string.format("Rank%03d", index), board)
		value.Value = 1000 - index
		value:SetAttribute("UserId", 1000 + index)
		value:SetAttribute("DisplayName", "P" .. index)
		value:SetAttribute("Username", "User" .. index)
	end
	board:SetAttribute("Version", 2)
	expect(rowCount(), 100, "full list count")
	expect(you:FindFirstChild("Rank").Text, "100+", "rank past the page")
	expect(you.Parent, root, "full list absorbed the personal card")
	for _, child in ipairs(board:GetChildren()) do if child:IsA("IntValue") then child:Destroy() end end
	board:SetAttribute("Version", 3)
	expect(rowCount(), 0, "cleared rows")
	expect(list:FindFirstChild("Empty").Visible, true, "empty restored")
	expect(you:FindFirstChild("Rank").Text, unranked, "cleared rank")
	local boards = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("SurfaceGui") and child.Name == "Kills" then table.insert(boards, child) end
	end
	expect(#boards, 1, "played-time model mounted a kills board")
	local model2 = new("Model", "LeaderboardKills")
	local display = new("Part", "Display", model2)
	display.Size = {X = 10, Y = 16, Z = 1}
	model2.Parent = workspace
	boards = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("SurfaceGui") and child.Name == "Kills" then table.insert(boards, child) end
	end
	expect(#boards, 2, "streamed board")
	for _, other in ipairs(boards) do
		assert(other.Parent == playerGui, "streamed gui parent")
		pinned(other:FindFirstChild("Board"))
	end
	local streamed = boards[1].Adornee == display and boards[1] or boards[2]
	expect(streamed.Adornee, display, "streamed adornee")
	expect(streamed.Face, "NormalId.Front", "default face")
end

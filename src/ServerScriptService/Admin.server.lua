-- Admin actions. AdminList is the only privilege list. Every remote checks it again.
-- Giving coins uses GrantCoins, so held and lifetime both rise and a repeated
-- purchase id cannot pay twice. Resets go through the owning scripts so a
-- player who is in this server is not restored from the old session on leave.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminList = require(script.Parent:WaitForChild("AdminList"))

local COLOR_KEYS = {Gun = "GrappleGunColor", Rope = "GrappleRopeColor", Bomb = "BombColor"}
local RESETS = {coins = "AdminCoins", kills = "AdminKills", time = "AdminPlayedTime", upgrades = "AdminUpgrades"}

local stores = {}
local lastAction = {}
local palettes

local function storeNamed(name)
	local found = stores[name]
	if found ~= nil then return found or nil end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	stores[name] = ok and result or false
	return ok and result or nil
end

local function ensureRemote(name)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local requestRemote = ensureRemote("AdminRequest")
local resultRemote = ensureRemote("AdminResult")
local noclipRemote = ensureRemote("AdminNoclip")

local function reply(player, ok, action, message, profile, extra)
	if player.Parent ~= Players then return end
	local payload = {
		ok = ok == true, action = action, message = message, profile = profile,
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do payload[key] = value end
	end
	resultRemote:FireClient(player, payload)
end

local function trim(text)
	if type(text) ~= "string" then return "" end
	return (string.match(text, "^%s*(.-)%s*$"))
end

local function resolveUser(query)
	query = trim(query)
	if query == "" then return nil, "Enter a user id or username." end
	local asNumber = tonumber(query)
	if asNumber then
		if asNumber ~= math.floor(asNumber) or asNumber < 1 or asNumber >= 2 ^ 53 then
			return nil, "That user id is not valid."
		end
		local name
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(asNumber)
		end)
		if ok and type(result) == "string" and result ~= "" then name = result end
		return asNumber, name
	end
	if #query < 3 or #query > 20 or string.match(query, "[^%w_]") then
		return nil, "That username is not valid."
	end
	local ok, result = pcall(function()
		return Players:GetUserIdFromNameAsync(query)
	end)
	if not ok or type(result) ~= "number" then return nil, "No user with that name." end
	return result, query
end

local function invoke(name, ...)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		local ok, found = pcall(function()
			return ReplicatedStorage:WaitForChild(name, 5)
		end)
		remote = ok and found or nil
	end
	if not remote then return nil end
	local packed = table.pack(...)
	local ok, result = pcall(function()
		return remote:Invoke(table.unpack(packed, 1, packed.n))
	end)
	if not ok then return nil end
	return result
end

local function readRecord(storeName, userId)
	local dataStore = storeNamed(storeName)
	if not dataStore then return nil end
	local ok, data = pcall(function()
		return dataStore:GetAsync("player_" .. userId)
	end)
	if ok and type(data) == "table" then return data end
	return nil
end

local function numberOr(value, fallback)
	local amount = tonumber(value)
	if not amount then return fallback end
	return math.max(0, math.floor(amount))
end

local function clampRank(value)
	return math.clamp(numberOr(value, 0), 0, 10)
end

local function coinTotals(data)
	local held = 0
	local earned = nil
	if type(data) == "table" then
		held = numberOr(data.coins, 0)
		earned = tonumber(data.earned)
	end
	if earned == nil then earned = held else earned = math.max(0, math.floor(earned)) end
	return held, earned
end

local function colorPalettes()
	if palettes then return palettes end
	palettes = require(ReplicatedStorage:WaitForChild("ItemColors"))
	return palettes
end

local function normalizeColor(target, colorName)
	if target ~= "Gun" and target ~= "Rope" and target ~= "Bomb" then return nil end
	colorName = trim(colorName)
	if colorName == "" then return nil end
	if target == "Bomb" and colorName == "Teal" then colorName = "Mint" end
	if target == "Bomb" and colorName == "Lime" then colorName = "Green" end
	local colors = colorPalettes()
	if colorName ~= "Rainbow" and (type(colors[target]) ~= "table" or colors[target][colorName] == nil) then
		return nil
	end
	return colorName
end

local function isBanned(data)
	return type(data) == "table" and data.banned == true
end

local function lookupProfile(userId, username)
	local player = Players:GetPlayerByUserId(userId)
	local liveCoins = invoke("AdminCoins", "read", userId)
	local liveKills = invoke("AdminKills", "read", userId)
	local liveTime = invoke("AdminPlayedTime", "read", userId)
	local liveRanks = invoke("AdminUpgrades", "read", userId)
	local coinRecord = (type(liveCoins) ~= "table") and readRecord("GrappleCoins_v1", userId) or nil
	local killRecord = (type(liveKills) ~= "table") and readRecord("GrappleKills_v1", userId) or nil
	local timeRecord = (type(liveTime) ~= "table") and readRecord("GrapplePlayedTime_v1", userId) or nil
	local rankRecord = (type(liveRanks) ~= "table") and readRecord("GrappleUpgrades_v1", userId) or nil
	local colorRecord = readRecord("GrappleCosmetics_v1", userId)
	local banRecord = readRecord("GrappleBans_v1", userId)
	local held, earned = coinTotals(coinRecord)
	if type(liveCoins) == "table" then
		held = numberOr(liveCoins.coins, 0)
		earned = numberOr(liveCoins.earned, 0)
	end
	local kills = type(liveKills) == "table" and numberOr(liveKills.kills, 0) or numberOr(killRecord and killRecord.kills, 0)
	local seconds = type(liveTime) == "table" and numberOr(liveTime.seconds, 0) or numberOr(timeRecord and timeRecord.seconds, 0)
	local ranks = type(liveRanks) == "table" and liveRanks or rankRecord or {}
	local function colorOf(key)
		if player then
			local live = player:GetAttribute(key)
			if type(live) == "string" and live ~= "" then return live end
		end
		local saved = colorRecord and colorRecord[key]
		if type(saved) == "string" and saved ~= "" then return saved end
		return "Default"
	end
	local display = player and player.DisplayName
	if type(display) ~= "string" or display == "" then
		display = coinRecord and coinRecord.name or killRecord and killRecord.name or username or "Player"
	end
	if type(username) ~= "string" or username == "" then
		username = player and player.Name or coinRecord and coinRecord.username or "Unknown"
	end
	return {
		userId = userId,
		username = username,
		displayName = display,
		online = player ~= nil,
		coins = held,
		coinsEarned = earned,
		kills = kills,
		playedSeconds = seconds,
		speed = clampRank(ranks.speed),
		distance = clampRank(ranks.distance),
		duration = clampRank(ranks.duration),
		resistance = clampRank(ranks.resistance),
		gun = colorOf("GrappleGunColor"),
		rope = colorOf("GrappleRopeColor"),
		bomb = colorOf("BombColor"),
		banned = isBanned(banRecord),
		banReason = isBanned(banRecord) and type(banRecord.reason) == "string" and banRecord.reason or "",
		admin = AdminList.IsAdmin(userId),
	}
end

local function giveCoins(admin, query, amountText)
	local userId, nameOrError = resolveUser(query)
	if not userId then return reply(admin, false, "grant", nameOrError) end
	local amount = tonumber(amountText)
	if not amount then return reply(admin, false, "grant", "Enter a coin amount.") end
	amount = math.floor(amount)
	if amount <= 0 then return reply(admin, false, "grant", "Amount has to be at least 1.") end
	if amount > 100000000 then return reply(admin, false, "grant", "Amount is too large.") end
	local granted = invoke("AdminCoins", "grant", userId, amount)
	if granted ~= true then return reply(admin, false, "grant", "Could not give those coins.") end
	local who = nameOrError or tostring(userId)
	reply(admin, true, "grant", "Gave " .. tostring(amount) .. " coins to " .. who .. ". Lifetime coins were not changed.")
end

local function onlinePlayer(userId)
	if type(userId) ~= "number" then return nil end
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent == Players then return player end
	return nil
end

local function listPlayers(admin)
	local rows = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local display = other.DisplayName
		if type(display) ~= "string" or display == "" then display = other.Name end
		rows[#rows + 1] = {userId = other.UserId, username = other.Name, displayName = display}
	end
	table.sort(rows, function(a, b)
		return string.lower(tostring(a.username)) < string.lower(tostring(b.username))
	end)
	reply(admin, true, "players", tostring(#rows) .. " in this server.", nil, {players = rows})
end

local function rootPart(target)
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return nil
end

local function moveTo(who, destination)
	local root = rootPart(who)
	local there = rootPart(destination)
	if not root or not there then return false end
	root.CFrame = there.CFrame * CFrame.new(0, 3, -4)
	return true
end

local function teleport(admin, userId, bring)
	local target = onlinePlayer(userId)
	if not target then return reply(admin, false, bring and "bring" or "goto", "That player is not in this server.") end
	local moved = bring and moveTo(target, admin) or moveTo(admin, target)
	if not moved then
		return reply(admin, false, bring and "bring" or "goto", "Could not find both characters.")
	end
	local who = target.DisplayName ~= "" and target.DisplayName or target.Name
	if bring then
		reply(admin, true, "bring", "Teleported " .. who .. " to you.")
	else
		reply(admin, true, "goto", "Teleported you to " .. who .. ".")
	end
end

local function livingHumanoid(target)
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or (humanoid.Health or 0) <= 0 then return nil end
	return humanoid
end

-- Applied to the current character only. A respawn builds a new humanoid, so
-- the boost is gone after they die.
local function boost(admin, userId, kind)
	local target = onlinePlayer(userId)
	if not target then return reply(admin, false, "boost", "That player is not in this server.") end
	local humanoid = livingHumanoid(target)
	if not humanoid then return reply(admin, false, "boost", "They have no character.") end
	local who = target.DisplayName ~= "" and target.DisplayName or target.Name
	if kind == "speed" then
		humanoid.WalkSpeed = 24
		reply(admin, true, "boost", "Set " .. who .. "'s speed to 24.")
	elseif kind == "jump" then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 80
		reply(admin, true, "boost", "Set " .. who .. "'s jump power to 80.")
	else
		reply(admin, false, "boost", "Unknown boost.")
	end
end

local function resetStats(admin, query, kind)
	if kind ~= "all" and not RESETS[kind] then
		return reply(admin, false, "reset", "Choose which stats to reset.")
	end
	local userId, nameOrError = resolveUser(query)
	if not userId then return reply(admin, false, "reset", nameOrError) end
	local kinds = kind == "all" and {"coins", "kills", "time", "upgrades"} or {kind}
	for _, stat in ipairs(kinds) do
		if invoke(RESETS[stat], "reset", userId) ~= true then
			return reply(admin, false, "reset", "Could not reset " .. stat .. ".")
		end
	end
	local who = nameOrError or tostring(userId)
	reply(admin, true, "reset", "Reset " .. (kind == "all" and "all stats" or kind) .. " for " .. who .. ".")
end

local function setColor(admin, query, target, colorName)
	local normalized = normalizeColor(target, colorName)
	if not normalized then return reply(admin, false, "color", "That color is not in the palette.") end
	local userId, nameOrError = resolveUser(query)
	if not userId then return reply(admin, false, "color", nameOrError) end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local started = os.clock()
		while player.Parent == Players and player:GetAttribute("SettingsLoaded") ~= true and os.clock() - started < 20 do
			task.wait(0.1)
		end
		if player:GetAttribute("SettingsLoaded") ~= true then
			return reply(admin, false, "color", "Their settings are still loading.")
		end
		if invoke("AdminSetGrappleColor", userId, target, normalized) ~= true then
			return reply(admin, false, "color", "Could not set that color.")
		end
	else
		local dataStore = storeNamed("GrappleCosmetics_v1")
		if not dataStore then return reply(admin, false, "color", "Could not save that color.") end
		local key = COLOR_KEYS[target]
		local ok = pcall(function()
			dataStore:UpdateAsync("player_" .. userId, function(previous)
				local record = type(previous) == "table" and previous or {}
				record[key] = normalized
				return record
			end)
		end)
		if not ok then return reply(admin, false, "color", "Could not save that color.") end
	end
	local who = nameOrError or tostring(userId)
	reply(admin, true, "color", "Set " .. string.lower(target) .. " color to " .. normalized .. " for " .. who .. ".")
end

local function setBan(admin, query, reason, banned)
	local userId, nameOrError = resolveUser(query)
	if not userId then return reply(admin, false, "ban", nameOrError) end
	if AdminList.IsAdmin(userId) then
		return reply(admin, false, "ban", "That player is an admin.")
	end
	reason = trim(reason)
	reason = string.gsub(reason, "[%c]", " ")
	if #reason > 80 then reason = string.sub(reason, 1, 80) end
	local dataStore = storeNamed("GrappleBans_v1")
	if not dataStore then return reply(admin, false, "ban", "Could not save that ban.") end
	local ok = pcall(function()
		dataStore:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {}
			record.banned = banned
			record.reason = banned and reason or ""
			record.by = admin.UserId
			record.at = os.time()
			return record
		end)
	end)
	if not ok then return reply(admin, false, "ban", "Could not save that ban.") end
	local target = Players:GetPlayerByUserId(userId)
	if banned and target then
		target:Kick(reason ~= "" and ("Banned: " .. reason) or "Banned from this game.")
	end
	local who = nameOrError or tostring(userId)
	reply(admin, true, "ban", (banned and "Banned " or "Unbanned ") .. who .. ".")
end

local function handle(player, payload)
	if not AdminList.IsAdmin(player.UserId) then
		reply(player, false, "denied", "Not allowed.")
		return
	end
	if type(payload) ~= "table" or type(payload.action) ~= "string" then return end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.25 then
		reply(player, false, payload.action, "Slow down.")
		return
	end
	lastAction[player] = now
	local action = payload.action
	if action == "grant" then
		giveCoins(player, payload.user, payload.amount)
	elseif action == "players" then
		listPlayers(player)
	elseif action == "bring" then
		teleport(player, payload.userId, true)
	elseif action == "goto" then
		teleport(player, payload.userId, false)
	elseif action == "boost" then
		boost(player, payload.userId, payload.kind)
	elseif action == "lookup" then
		local userId, nameOrError = resolveUser(payload.user)
		if not userId then
			reply(player, false, "lookup", nameOrError)
			return
		end
		local profile = lookupProfile(userId, nameOrError)
		reply(player, true, "lookup", "Loaded " .. profile.username .. ".", profile)
	elseif action == "ban" then
		setBan(player, payload.user, payload.reason, true)
	elseif action == "unban" then
		setBan(player, payload.user, "", false)
	elseif action == "reset" then
		resetStats(player, payload.user, payload.kind)
	elseif action == "color" then
		setColor(player, payload.user, payload.target, payload.color)
	else
		reply(player, false, action, "Unknown action.")
	end
end

noclipRemote.OnServerEvent:Connect(function(player)
	if not AdminList.IsAdmin(player.UserId) then return end
	player:SetAttribute("Noclip", player:GetAttribute("Noclip") ~= true)
end)

requestRemote.OnServerEvent:Connect(function(player, payload)
	local ok, err = pcall(handle, player, payload)
	if not ok then
		warn("[Admin] " .. tostring(err))
		reply(player, false, "error", "Something went wrong.")
	end
end)

local function bannedRecord(userId)
	if AdminList.IsAdmin(userId) then return nil end
	return readRecord("GrappleBans_v1", userId)
end

local function joined(player)
	local record = bannedRecord(player.UserId)
	if isBanned(record) then
		local reason = type(record.reason) == "string" and record.reason or ""
		player:Kick(reason ~= "" and ("Banned: " .. reason) or "Banned from this game.")
		return
	end
	if AdminList.IsAdmin(player.UserId) then
		player:SetAttribute("Admin", true)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(joined, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(joined, player)
end

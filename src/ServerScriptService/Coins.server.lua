-- Coins is the balance a player is holding. Earned is the lifetime total and only
-- goes up, so spending coins does not lower LeaderboardCoins. GrappleCoins_v1
-- keeps both. GrappleCoinsRank_v1 is the public top-100 board.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PAGE_SIZE = 100
local REFRESH_EVERY = 60

local store = DataStoreService:GetDataStore("GrappleCoins_v1")
local ordered
pcall(function()
	ordered = DataStoreService:GetOrderedDataStore("GrappleCoinsRank_v1")
end)

local board = ReplicatedStorage:FindFirstChild("CoinsBoard")
if not board then
	board = Instance.new("Folder")
	board.Name = "CoinsBoard"
	board.Parent = ReplicatedStorage
end

local profiles = {}
local sessions = {}
local nextRefresh = 0

local function displayName(player)
	if type(player.DisplayName) == "string" and player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function shortName(name)
	name = tostring(name or "Player")
	if #name > 24 then name = string.sub(name, 1, 24) end
	return name
end

local function rememberProfile(userId, display, username)
	local profile = profiles[userId]
	if not profile then
		profile = {}
		profiles[userId] = profile
	end
	if type(display) == "string" and display ~= "" then profile.display = display end
	if type(username) == "string" and username ~= "" then profile.username = username end
	return profile
end

local function remember(player)
	if not player or type(player.UserId) ~= "number" then return "Player" end
	local display = displayName(player)
	rememberProfile(player.UserId, display, player.Name)
	return display
end

-- Ordered ranks only store a user id. A cached nickname from an earlier visit
-- wins when the username API cannot recover a display name.
local function profileFor(userId)
	local online = Players:GetPlayerByUserId(userId)
	if online then return rememberProfile(userId, displayName(online), online.Name) end
	local profile = profiles[userId]
	if not profile or not profile.username then
		local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
		if ok and type(name) == "string" and name ~= "" then
			profile = rememberProfile(userId, profile and profile.display, name)
		end
	end
	profile = profile or {}
	local username = profile.username or "Player"
	return {display = profile.display or username, username = username}
end

local function publishBoard(ranked)
	for _, child in ipairs(board:GetChildren()) do
		if child:IsA("IntValue") then child:Destroy() end
	end
	for index, entry in ipairs(ranked) do
		local value = Instance.new("IntValue")
		value.Name = string.format("Rank%03d", index)
		value.Value = entry.coins
		value:SetAttribute("UserId", entry.id)
		value:SetAttribute("DisplayName", entry.display)
		value:SetAttribute("Username", entry.username)
		value.Parent = board
	end
	board:SetAttribute("Version", (board:GetAttribute("Version") or 0) + 1)
end

local refreshing = false
local refreshAgain = false
local function requestRefresh()
	if refreshing then
		refreshAgain = true
		return
	end
	refreshing = true
	task.spawn(function()
		repeat
			refreshAgain = false
			local byId = {}
			if ordered then
				local ok, pages = pcall(function() return ordered:GetSortedAsync(false, PAGE_SIZE) end)
				if ok and pages then
					for _, entry in ipairs(pages:GetCurrentPage()) do
						local id = tonumber(entry.key)
						local coins = math.floor(tonumber(entry.value) or 0)
						if id and coins > 0 then byId[id] = {id = id, coins = coins} end
					end
				end
			end
			-- This server's loaded total sits on top of the saved ranking so a
			-- new coin shows before the ordered write finishes.
			for player, state in pairs(sessions) do
				if player.Parent == Players and state.loaded and (state.lifetime or 0) > 0 then
					local total = state.lifetime
					local existing = byId[player.UserId]
					if existing and existing.coins > total then
						existing.display = existing.display or displayName(player)
						existing.username = existing.username or player.Name
					else
						byId[player.UserId] = {
							id = player.UserId, coins = total,
							display = displayName(player), username = player.Name,
						}
					end
				end
			end
			local ranked = {}
			for _, entry in pairs(byId) do table.insert(ranked, entry) end
			table.sort(ranked, function(a, b)
				if a.coins == b.coins then return a.id < b.id end
				return a.coins > b.coins
			end)
			while #ranked > PAGE_SIZE do table.remove(ranked) end
			for _, entry in ipairs(ranked) do
				local profile = profileFor(entry.id)
				entry.display = shortName(entry.display or profile.display)
				entry.username = shortName(entry.username or profile.username)
			end
			publishBoard(ranked)
		until not refreshAgain
		refreshing = false
	end)
end

-- One ordered write per player each minute. A newer total replaces a queued one.
local pendingRanks = {}
local function queueRank(userId, total)
	if type(userId) ~= "number" then return end
	total = math.floor(tonumber(total) or 0)
	if total <= 0 then return end
	local queued = pendingRanks[userId]
	if not queued or total > queued then pendingRanks[userId] = total end
end

local function flushRanks()
	local batch = pendingRanks
	pendingRanks = {}
	if not ordered then return end
	for userId, total in pairs(batch) do
		pcall(function()
			ordered:UpdateAsync(tostring(userId), function(previous)
				if total > (tonumber(previous) or 0) then return total end
			end)
		end)
	end
end

-- Older rows stored only the held total. Coins could not be spent then, so that
-- number is the lifetime total until an earned field exists.
local function heldAndEarned(data)
	local held = 0
	local earned = nil
	if type(data) == "table" then
		held = math.max(0, math.floor(tonumber(data.coins) or 0))
		earned = tonumber(data.earned)
	end
	if earned == nil then earned = held else earned = math.max(0, math.floor(earned)) end
	return held, earned
end

-- A loaded zero stays nil. The board shows that as 0, and nil still means no coins yet.
local function publishEarned(player, total)
	if player and player.Parent == Players and total > 0 then
		player:SetAttribute("CoinsEarned", total)
	end
end

local function save(player, state)
	while state.saving do task.wait() end
	if not state.loaded or state.earned == state.saved then return end
	state.saving = true
	local earned = state.earned
	local ok, data
	for attempt = 1, 3 do
		ok, data = pcall(function()
			return store:UpdateAsync("player_" .. player.UserId, function(previous)
				local record = type(previous) == "table" and previous or {coins = 0, sessions = {}}
				record.sessions = record.sessions or {}
				local checkpoint = record.sessions[state.id]
				local alreadySaved = checkpoint and checkpoint.earned or 0
				local delta = math.max(0, earned - alreadySaved)
				local held, lifetime = heldAndEarned(record)
				record.coins = held + delta
				record.earned = lifetime + delta
				record.sessions[state.id] = {earned = earned, at = os.time()}
				local profile = profiles[player.UserId]
				if profile then
					if type(profile.display) == "string" and profile.display ~= "" then record.name = profile.display end
					if type(profile.username) == "string" and profile.username ~= "" then record.username = profile.username end
				end
				-- Retain recent session checkpoints so retries cannot award twice.
				for id, entry in pairs(record.sessions) do
					if id ~= state.id and os.time() - entry.at > 7 * 86400 then record.sessions[id] = nil end
				end
				return record
			end)
		end)
		if ok then break end
		if attempt < 3 then task.wait(attempt) end
	end
	if ok then
		state.saved = earned
		state.base = data.coins - earned
		state.lifetime = math.max(state.lifetime or 0, math.floor(tonumber(data.earned) or 0))
		player:SetAttribute("Coins", state.base + state.earned)
		publishEarned(player, state.lifetime)
		queueRank(player.UserId, state.lifetime)
	else
		warn("[Coins] Save failed for " .. player.Name .. ": " .. tostring(data))
	end
	state.saving = false
end

local function joined(player)
	if sessions[player] then return end
	remember(player)
	local state = {id = HttpService:GenerateGUID(false), started = os.clock(), earned = 0, saved = 0, base = 0, lifetime = 0}
	sessions[player] = state
	player:SetAttribute("Coins", 0)
	task.spawn(function()
		while sessions[player] == state and not state.loaded do
			local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
			if sessions[player] ~= state or state.loaded then return end
			if ok then
				local held, earned = heldAndEarned(data)
				if type(data) == "table" then rememberProfile(player.UserId, data.name, data.username) end
				remember(player)
				state.base = held
				state.lifetime = earned + state.earned
				state.loaded = true
				player:SetAttribute("Coins", state.base + state.earned)
				publishEarned(player, state.lifetime)
				queueRank(player.UserId, state.lifetime)
			else
				warn("[Coins] Load failed for " .. player.Name .. "; retrying")
				task.wait(10)
			end
		end
	end)
end

RunService.Heartbeat:Connect(function()
	for player, state in pairs(sessions) do
		local earned = math.floor((os.clock() - state.started) / 60)
		if earned > state.earned then
			local gain = earned - state.earned
			state.earned = earned
			if state.loaded then
				state.lifetime = (state.lifetime or 0) + gain
				publishEarned(player, state.lifetime)
			end
			player:SetAttribute("Coins", state.base + earned)
			if state.loaded and not state.saving then task.spawn(save, player, state) end
		end
	end
	if os.clock() >= nextRefresh then
		nextRefresh = os.clock() + REFRESH_EVERY
		flushRanks()
		requestRefresh()
	end
end)
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	remember(player)
	local state = sessions[player]
	if not state then return end
	sessions[player] = nil
	save(player, state)
end)
for _, player in ipairs(Players:GetPlayers()) do joined(player) end
game:BindToClose(function()
	local remaining = 0
	for player, state in pairs(sessions) do
		remaining += 1
		task.spawn(function()
			save(player, state)
			remaining -= 1
		end)
	end
	while remaining > 0 do task.wait() end
	flushRanks()
end)

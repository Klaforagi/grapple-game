local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local PAGE_SIZE = 100
local SAVE_EVERY = 60
local REFRESH_EVERY = 15

local store, ordered
pcall(function()
	store = DataStoreService:GetDataStore("GrapplePlayedTime_v1")
	ordered = DataStoreService:GetOrderedDataStore("GrapplePlayedTimeRank_v1")
end)

local board = ReplicatedStorage:FindFirstChild("PlayedTimeBoard")
if not board then
	board = Instance.new("Folder")
	board.Name = "PlayedTimeBoard"
	board.Parent = ReplicatedStorage
end

local sessions, profiles = {}, {}
local nextRefresh = 0

local function playerDisplay(player)
	if type(player.DisplayName) == "string" and player.DisplayName ~= "" then return player.DisplayName end
	return player.Name
end

local function shortName(name)
	name = tostring(name or "Player")
	if #name > 24 then name = string.sub(name, 1, 24) end
	return name
end

local function currentSession(state)
	return math.max(0, math.floor(os.clock() - state.started))
end

local function publish(entries)
	for _, child in ipairs(board:GetChildren()) do
		if child:IsA("IntValue") then child:Destroy() end
	end
	for index, entry in ipairs(entries) do
		local value = Instance.new("IntValue")
		value.Name = string.format("Rank%03d", index)
		value.Value = entry.seconds
		value:SetAttribute("UserId", entry.id)
		value:SetAttribute("DisplayName", entry.display)
		value:SetAttribute("Username", entry.username)
		value.Parent = board
	end
	board:SetAttribute("Version", (board:GetAttribute("Version") or 0) + 1)
end

local function remember(userId, display, username)
	local profile = profiles[userId]
	if not profile then
		profile = {}
		profiles[userId] = profile
	end
	if type(display) == "string" and display ~= "" then profile.display = display end
	if type(username) == "string" and username ~= "" then profile.username = username end
	return profile
end

-- Ordered ranks only store a user id. The username API cannot recover a display
-- name, so a cached nickname from an earlier visit wins when we have one.
local function profileFor(userId)
	local online = Players:GetPlayerByUserId(userId)
	if online then return remember(userId, playerDisplay(online), online.Name) end
	local profile = profiles[userId]
	if not profile or not profile.username then
		local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
		if ok and type(name) == "string" and name ~= "" then
			profile = remember(userId, profile and profile.display, name)
		end
	end
	profile = profile or {}
	local username = profile.username or "Player"
	return {display = profile.display or username, username = username}
end

local function refresh()
	local byId = {}
	if ordered then
		local ok, pages = pcall(function() return ordered:GetSortedAsync(false, PAGE_SIZE) end)
		if ok and pages then
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local id = tonumber(entry.key)
				local seconds = math.floor(tonumber(entry.value) or 0)
				if id and seconds > 0 then byId[id] = {id = id, seconds = seconds} end
			end
		end
	end
	-- Seconds still in this visit sit on top of the saved ranking so the board
	-- moves before the next write. The saved copy stays idempotent.
	for player, state in pairs(sessions) do
		if player.Parent then
			local seconds = (state.base or 0) + currentSession(state)
			local existing = byId[player.UserId]
			if seconds > 0 and (not existing or seconds >= existing.seconds) then
				byId[player.UserId] = {
					id = player.UserId, seconds = seconds,
					display = playerDisplay(player), username = player.Name,
				}
			elseif existing then
				existing.display = existing.display or playerDisplay(player)
				existing.username = existing.username or player.Name
			end
		end
	end
	local entries = {}
	for _, entry in pairs(byId) do table.insert(entries, entry) end
	table.sort(entries, function(a, b)
		if a.seconds == b.seconds then return a.id < b.id end
		return a.seconds > b.seconds
	end)
	while #entries > PAGE_SIZE do table.remove(entries) end
	for _, entry in ipairs(entries) do
		local profile = profileFor(entry.id)
		entry.display = shortName(entry.display or profile.display)
		entry.username = shortName(entry.username or profile.username)
	end
	publish(entries)
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
			refresh()
		until not refreshAgain
		refreshing = false
	end)
end

local function save(player, state)
	while state.saving do task.wait() end
	local session = currentSession(state)
	state.session = session
	if not state.loaded or not store or session == state.savedSession then return end
	state.saving = true
	local ok, data
	for attempt = 1, 3 do
		ok, data = pcall(function()
			return store:UpdateAsync("player_" .. player.UserId, function(previous)
				local record = type(previous) == "table" and previous or {seconds = 0, sessions = {}}
				record.sessions = record.sessions or {}
				local checkpoint = record.sessions[state.id]
				local already = checkpoint and checkpoint.seconds or 0
				record.seconds = math.max(0, math.floor(record.seconds or 0)) + math.max(0, session - already)
				record.sessions[state.id] = {seconds = session, at = os.time()}
				record.name = playerDisplay(player)
				record.username = player.Name
				for id, entry in pairs(record.sessions) do
					if id ~= state.id and os.time() - (entry.at or 0) > 7 * 86400 then record.sessions[id] = nil end
				end
				return record
			end)
		end)
		if ok then break end
		if attempt < 3 then task.wait(attempt) end
	end
	if ok and type(data) == "table" then
		state.savedSession = session
		state.base = math.max(0, math.floor(data.seconds or 0) - session)
		state.session = currentSession(state)
		player:SetAttribute("PlayedSeconds", state.base + state.session)
		remember(player.UserId, playerDisplay(player), player.Name)
		if ordered and data.seconds > 0 then
			pcall(function()
				ordered:UpdateAsync(tostring(player.UserId), function(previous)
					if data.seconds > (tonumber(previous) or 0) then return math.floor(data.seconds) end
				end)
			end)
		end
		requestRefresh()
	else
		warn("[PlayedTime] Save failed for " .. player.Name .. ": " .. tostring(data))
	end
	state.saving = false
end

local function load(player, state)
	if not store then
		state.loaded = true
		player:SetAttribute("PlayedSeconds", state.base + currentSession(state))
		return
	end
	while sessions[player] == state and not state.loaded do
		local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
		if sessions[player] ~= state then return end
		if ok then
			state.base = math.max(0, math.floor(type(data) == "table" and tonumber(data.seconds) or 0))
			if type(data) == "table" then remember(player.UserId, data.name, data.username) end
			state.loaded = true
			player:SetAttribute("PlayedSeconds", state.base + currentSession(state))
		else
			warn("[PlayedTime] Load failed for " .. player.Name .. "; retrying")
			task.wait(10)
		end
	end
end

local function joined(player)
	if sessions[player] then return end
	local state = {
		id = HttpService:GenerateGUID(false),
		started = os.clock(), base = 0, session = 0, savedSession = 0,
	}
	sessions[player] = state
	player:SetAttribute("PlayedSeconds", 0)
	task.spawn(load, player, state)
end

RunService.Heartbeat:Connect(function()
	for player, state in pairs(sessions) do
		local session = currentSession(state)
		if session ~= state.session then
			state.session = session
			player:SetAttribute("PlayedSeconds", (state.base or 0) + session)
		end
		if state.loaded and session - state.savedSession >= SAVE_EVERY and not state.saving then
			task.spawn(save, player, state)
		end
	end
	if os.clock() >= nextRefresh then
		nextRefresh = os.clock() + REFRESH_EVERY
		requestRefresh()
	end
end)

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
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
end)

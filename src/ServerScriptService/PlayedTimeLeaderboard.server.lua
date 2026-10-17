local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local IS_STUDIO = RunService:IsStudio()

local PAGE_SIZE = 100
local SAVE_EVERY = 60
local REFRESH_EVERY = 60

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
	if IS_STUDIO then return 0 end
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

-- One ordered write per player each minute. A newer total replaces a queued one.
-- rankEpoch lets an admin reset drop the board. A flush that already copied the
-- old total sees the new epoch and does not write that total back.
local pendingRanks = {}
local rankEpoch = {}
local function queueRank(userId, total)
	if type(userId) ~= "number" then return end
	total = math.floor(tonumber(total) or 0)
	if total <= 0 then return end
	local epoch = rankEpoch[userId] or 0
	local queued = pendingRanks[userId]
	if not queued or queued.epoch ~= epoch or total > queued.total then
		pendingRanks[userId] = {total = total, epoch = epoch}
	end
end

local function flushRanks()
	local batch = pendingRanks
	pendingRanks = {}
	if not ordered then return end
	for userId, queued in pairs(batch) do
		local total, epoch = queued.total, queued.epoch
		if (rankEpoch[userId] or 0) == epoch then
			pcall(function()
				ordered:UpdateAsync(tostring(userId), function(previous)
					if total > (tonumber(previous) or 0) then return total end
				end)
			end)
		end
	end
end

local function forceRank(userId, total)
	rankEpoch[userId] = (rankEpoch[userId] or 0) + 1
	pendingRanks[userId] = nil
	if not ordered then return end
	pcall(function()
		if total <= 0 then
			ordered:RemoveAsync(tostring(userId))
		else
			ordered:SetAsync(tostring(userId), total)
		end
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
		queueRank(player.UserId, data.seconds)
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
		flushRanks()
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
	flushRanks()
end)

-- The next save adds (session - checkpoint) onto the stored seconds. A reset
-- has to zero the checkpoint and the live session together, or leaving puts
-- the time before the reset back on the record.
local function sessionFor(userId)
	for player, state in pairs(sessions) do
		if player.UserId == userId then return player, state end
	end
end

local function adminReadPlayed(userId)
	local player, state = sessionFor(userId)
	if not player or not state or not state.loaded then return nil end
	return {seconds = (state.base or 0) + currentSession(state)}
end

local function adminResetPlayed(userId)
	if type(userId) ~= "number" then return false end
	local player, state = sessionFor(userId)
	if state and not state.loaded then
		local started = os.clock()
		while sessions[player] == state and not state.loaded and os.clock() - started < 20 do
			task.wait(0.1)
		end
		if sessions[player] ~= state then state = nil end
	end
	if player and sessions[player] and not sessions[player].loaded then return false end
	state = player and sessions[player]
	if state then
		while state.saving do task.wait() end
		if sessions[player] ~= state then state = nil end
	end
	if state then state.saving = true end
	local ok = true
	if store then
		local savedOk, data = pcall(function()
			return store:UpdateAsync("player_" .. userId, function(previous)
				local record = type(previous) == "table" and previous or {seconds = 0, sessions = {}}
				record.sessions = record.sessions or {}
				record.seconds = 0
				if state then record.sessions[state.id] = {seconds = 0, at = os.time()} end
				return record
			end)
		end)
		ok = savedOk and type(data) == "table"
	end
	if state then
		if ok and player and sessions[player] == state then
			state.started = os.clock()
			state.base = 0
			state.session = 0
			state.savedSession = 0
			player:SetAttribute("PlayedSeconds", 0)
		end
		state.saving = false
	end
	if ok then forceRank(userId, 0) requestRefresh() end
	return ok
end

local adminPlayed = Instance.new("BindableFunction")
adminPlayed.Name = "AdminPlayedTime"
adminPlayed.OnInvoke = function(action, userId)
	if action == "read" then return adminReadPlayed(userId) end
	if action == "reset" then return adminResetPlayed(userId) end
	return false
end
adminPlayed.Parent = ReplicatedStorage

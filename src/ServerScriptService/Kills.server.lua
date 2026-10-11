-- Lifetime kills stay on the player and in GrappleKills_v1. Nothing renders a
-- board yet. Each saved kill id is remembered so a retried write adds it once.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KillCredit = require(ReplicatedStorage.Modules:WaitForChild("KillCredit"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))

local store
local storeWarned = false
pcall(function()
	store = DataStoreService:GetDataStore("GrappleKills_v1")
end)

local names = {}
local entries = {}
local inflight = 0

local function displayName(player)
	if type(player.DisplayName) == "string" and player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function remember(player)
	if not player or type(player.UserId) ~= "number" then return "Player" end
	names[player.UserId] = displayName(player)
	return names[player.UserId]
end

local function findEntry(userId)
	for player, entry in pairs(entries) do
		if entry.userId == userId then return player, entry end
	end
end

local function newKillId()
	local id
	local ok = pcall(function()
		id = HttpService:GenerateGUID(false)
	end)
	if ok and type(id) == "string" and id ~= "" then return id end
	return tostring(os.clock()) .. "-" .. tostring(math.random(1, 1000000000))
end

local function publish(player, entry)
	if player and player.Parent == Players and entry.loaded then
		player:SetAttribute("Kills", entry.total)
	end
end

local function persist(userId, killId, name)
	if not store then return end
	inflight += 1
	local ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function()
			store:UpdateAsync("player_" .. userId, function(previous)
				local record = type(previous) == "table" and previous or {kills = 0, applied = {}}
				if type(record.applied) ~= "table" then record.applied = {} end
				if record.applied[killId] then return nil end
				record.kills = math.max(0, math.floor(tonumber(record.kills) or 0)) + 1
				record.applied[killId] = os.time()
				if type(name) == "string" and name ~= "" then record.name = name end
				local cutoff = os.time() - 7 * 86400
				for id, at in pairs(record.applied) do
					if type(at) ~= "number" or at < cutoff then record.applied[id] = nil end
				end
				return record
			end)
		end)
		if ok or attempt == 3 then break end
		task.wait(attempt)
	end
	inflight -= 1
	if not ok then warn("[Kills] Save failed for " .. tostring(userId) .. ": " .. tostring(err)) end
end

local function persistLater(userId, killId, name)
	task.spawn(persist, userId, killId, name)
end

local function award(userId)
	if type(userId) ~= "number" then return end
	if not store and not storeWarned then
		storeWarned = true
		warn("[Kills] DataStore unavailable; kill totals last for this server only")
	end
	local player, entry = findEntry(userId)
	local killId = newKillId()
	local name = names[userId]
	if entry and not entry.loaded then
		entry.queued[#entry.queued + 1] = killId
		return
	end
	if entry then
		entry.total += 1
		publish(player, entry)
	end
	if store then persistLater(userId, killId, name) end
end

local function killerDisplay(result)
	local online = Players:GetPlayerByUserId(result.killerId)
	if online then return remember(online) end
	if type(result.killerName) == "string" and result.killerName ~= "" then
		names[result.killerId] = result.killerName
		return result.killerName
	end
	return names[result.killerId] or "Player"
end

local function ropeColor(userId)
	local player = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local name = player and player:GetAttribute("GrappleRopeColor")
	if type(name) ~= "string" then return "" end
	return name
end

local function onKill(result, victimPlayer)
	if type(result) ~= "table" or type(result.killerId) ~= "number" then return end
	local victimName = victimPlayer and remember(victimPlayer) or "Player"
	local killerName = killerDisplay(result)
	if result.count then award(result.killerId) end
	if not result.show then return end
	local victimId = victimPlayer and victimPlayer.UserId or result.victimId
	if result.solo then
		local lines = KillCredit.SoloLines[result.cause]
		if type(lines) ~= "table" or #lines == 0 then return end
		local rope = ropeColor(victimId)
		Remotes.KillFeed:FireAllClients(victimName, victimName, result.cause, math.random(1, #lines), victimId, victimId, true, rope, rope)
		return
	end
	local lineKey = KillCredit.FeedKey(result.cause, result.source)
	local lines = KillCredit.Lines[lineKey]
	if type(lines) ~= "table" or #lines == 0 then return end
	Remotes.KillFeed:FireAllClients(killerName, victimName, lineKey, math.random(1, #lines), result.killerId, victimId, false, ropeColor(result.killerId), ropeColor(victimId))
end

KillCredit.SetListener(onKill)

local function applyQueued(player, entry, base)
	local queued = entry.queued
	entry.queued = {}
	entry.loaded = true
	entry.total = math.max(0, base) + #queued
	publish(player, entry)
	local name = names[entry.userId]
	for _, killId in ipairs(queued) do
		persistLater(entry.userId, killId, name)
	end
end

local function load(player, entry)
	if not store then
		applyQueued(player, entry, 0)
		return
	end
	while entries[player] == entry and not entry.loaded do
		local ok, data = pcall(function()
			return store:GetAsync("player_" .. player.UserId)
		end)
		if entries[player] ~= entry or entry.loaded then return end
		if ok then
			local base = math.max(0, math.floor(type(data) == "table" and tonumber(data.kills) or 0))
			if type(data) == "table" and type(data.name) == "string" and not names[player.UserId] then
				names[player.UserId] = data.name
			end
			applyQueued(player, entry, base)
			return
		end
		warn("[Kills] Load failed for " .. player.Name .. "; retrying")
		task.wait(10)
	end
end

local function flushEntry(player, entry)
	if entry.loaded then return end
	local queued = entry.queued
	entry.queued = {}
	entry.loaded = true
	for _, killId in ipairs(queued) do
		persist(entry.userId, killId, names[entry.userId])
	end
end

local function joined(player)
	if entries[player] then return end
	remember(player)
	local entry = {userId = player.UserId, total = 0, loaded = false, queued = {}}
	entries[player] = entry
	task.spawn(load, player, entry)
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	remember(player)
	local entry = entries[player]
	if not entry then return end
	local deadline = os.clock() + 12
	while entries[player] == entry and not entry.loaded and os.clock() < deadline do
		task.wait(0.1)
	end
	if entries[player] ~= entry then return end
	if not entry.loaded then flushEntry(player, entry) end
	entries[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	joined(player)
end

game:BindToClose(function()
	for player, entry in pairs(entries) do
		if not entry.loaded then flushEntry(player, entry) end
	end
	local deadline = os.clock() + 20
	while inflight > 0 and os.clock() < deadline do task.wait() end
end)

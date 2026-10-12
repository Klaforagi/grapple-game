-- Owns grapple upgrade ranks. Coin spends go through SpendCoins so lifetime
-- coins stay on the leaderboard. A failed rank save refunds the held coins.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Modules:WaitForChild("UpgradeCatalog"))

local store = DataStoreService:GetDataStore("GrappleUpgrades_v1")
local SpendCoins = ReplicatedStorage:WaitForChild("SpendCoins")
local RefundHeldCoins = ReplicatedStorage:WaitForChild("RefundHeldCoins")

local sessions = {}

local function ensureRemote(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local purchaseRemote = ensureRemote("PurchaseUpgrade")
local resultRemote = ensureRemote("UpgradeResult")

local function emptyRanks()
	local ranks = {}
	for _, stat in ipairs(Catalog.Stats) do ranks[stat.id] = 0 end
	return ranks
end

local function readRanks(data)
	local ranks = emptyRanks()
	if type(data) ~= "table" then return ranks end
	for _, stat in ipairs(Catalog.Stats) do
		ranks[stat.id] = Catalog.ClampRank(data[stat.id])
	end
	return ranks
end

local function publish(player, ranks)
	for _, stat in ipairs(Catalog.Stats) do
		player:SetAttribute(stat.attribute, ranks[stat.id])
	end
	player:SetAttribute("UpgradesLoaded", true)
end

local function saveRanks(player, state, ranks)
	while state.saving do task.wait() end
	state.saving = true
	local ok, err = pcall(function()
		store:UpdateAsync("player_" .. player.UserId, function(previous)
			local record = type(previous) == "table" and previous or {}
			for _, stat in ipairs(Catalog.Stats) do
				record[stat.id] = ranks[stat.id]
			end
			return record
		end)
	end)
	state.saving = false
	if not ok then warn("[Upgrades] Save failed for " .. player.Name .. ": " .. tostring(err)) end
	return ok
end

local function load(player)
	local state = sessions[player]
	if not state then return end
	while sessions[player] == state and not state.loaded do
		local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
		if sessions[player] ~= state then return end
		if ok then
			state.ranks = readRanks(data)
			state.loaded = true
			publish(player, state.ranks)
			return
		end
		warn("[Upgrades] Could not load " .. player.Name .. "; retrying")
		task.wait(10)
	end
end

local function reply(player, ok, statId, rank, reason)
	if player.Parent ~= Players then return end
	resultRemote:FireClient(player, ok, statId, rank, reason)
end

local function sessionFor(userId)
	for player, state in pairs(sessions) do
		if player.UserId == userId then return player, state end
	end
end

-- The receipt handler calls this after the player has picked an ability.
-- The same purchase id never raises a rank twice.
local function grantRobux(userId, purchaseId)
	if type(userId) ~= "number" or type(purchaseId) ~= "string" or purchaseId == "" then return false end
	local player, state = sessionFor(userId)
	if not player or not state or not state.loaded then return false end
	local stat = Catalog.Find(state.pendingRobux)
	while state.saving do task.wait() end
	if sessions[player] ~= state then return false end
	state.saving = true
	local outcome = nil
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {}
			if type(record.purchases) ~= "table" then record.purchases = {} end
			if record.purchases[purchaseId] then
				outcome = "repeat"
				return record
			end
			if not stat then
				outcome = "blocked"
				return record
			end
			local rank = Catalog.ClampRank(record[stat.id])
			if rank >= Catalog.MaxRank then
				outcome = "blocked"
				return record
			end
			record[stat.id] = rank + 1
			record.purchases[purchaseId] = stat.id
			outcome = "granted"
			return record
		end)
	end)
	if ok and type(data) == "table" and (outcome == "granted" or outcome == "repeat") and sessions[player] == state then
		state.ranks = readRanks(data)
		state.pendingRobux = nil
		publish(player, state.ranks)
	else
		outcome = nil
	end
	state.saving = false
	return outcome == "granted" or outcome == "repeat"
end

local grantUpgrade = Instance.new("BindableFunction")
grantUpgrade.Name = "GrantUpgradeRobux"
grantUpgrade.OnInvoke = grantRobux
grantUpgrade.Parent = ReplicatedStorage

local function purchase(player, statId, method)
	local state = sessions[player]
	if not state or not state.loaded then return end
	local stat = Catalog.Find(statId)
	if not stat then return end
	local rank = state.ranks[stat.id] or 0
	if method == "robux" then
		if rank >= Catalog.MaxRank then
			reply(player, false, stat.id, rank, "max")
			return
		end
		if type(Catalog.RobuxProductId) ~= "number" or Catalog.RobuxProductId <= 0 then
			reply(player, false, stat.id, rank, "unavailable")
			return
		end
		state.pendingRobux = stat.id
		reply(player, true, stat.id, rank, "prompt")
		return
	end
	if state.buying then
		reply(player, false, stat.id, rank, "busy")
		return
	end
	if rank >= Catalog.MaxRank then
		reply(player, false, stat.id, rank, "max")
		return
	end
	local cost = Catalog.Cost(rank)
	if not cost then return end
	state.buying = true
	local spentOk, spent = pcall(function()
		return SpendCoins:Invoke(player.UserId, cost)
	end)
	if not spentOk or spent ~= true then
		state.buying = false
		reply(player, false, stat.id, rank, "coins")
		return
	end
	local updated = {}
	for id, value in pairs(state.ranks) do updated[id] = value end
	updated[stat.id] = rank + 1
	local previous = state.ranks
	state.ranks = updated
	if not saveRanks(player, state, updated) then
		if state.ranks == updated then state.ranks = previous end
		pcall(function() RefundHeldCoins:Invoke(player.UserId, cost) end)
		state.buying = false
		reply(player, false, stat.id, rank, "save")
		return
	end
	player:SetAttribute(stat.attribute, rank + 1)
	state.buying = false
	reply(player, true, stat.id, rank + 1, "ok")
end

local function joined(player)
	if sessions[player] then return end
	sessions[player] = {saving = false, buying = false, loaded = false, ranks = emptyRanks()}
	task.spawn(load, player)
end

purchaseRemote.OnServerEvent:Connect(purchase)
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	local state = sessions[player]
	sessions[player] = nil
	if state and state.loaded then saveRanks(player, state, state.ranks) end
end)
for _, player in ipairs(Players:GetPlayers()) do joined(player) end
game:BindToClose(function()
	for player, state in pairs(sessions) do
		if state.loaded then saveRanks(player, state, state.ranks) end
	end
end)

-- Leave saves whatever ranks are in the session. A reset has to change that
-- table, or the old ranks are written again when the player leaves.
local function adminReadRanks(userId)
	local player, state = sessionFor(userId)
	if not player or not state or not state.loaded then return nil end
	local ranks = {}
	for _, stat in ipairs(Catalog.Stats) do
		ranks[stat.id] = state.ranks[stat.id] or 0
	end
	return ranks
end

local function adminResetRanks(userId)
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
	local ok = pcall(function()
		store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {}
			for _, stat in ipairs(Catalog.Stats) do
				record[stat.id] = 0
			end
			return record
		end)
	end)
	if state then
		if ok and player and sessions[player] == state then
			state.ranks = emptyRanks()
			publish(player, state.ranks)
		end
		state.saving = false
	end
	return ok
end

local adminUpgrades = Instance.new("BindableFunction")
adminUpgrades.Name = "AdminUpgrades"
adminUpgrades.OnInvoke = function(action, userId)
	if action == "read" then return adminReadRanks(userId) end
	if action == "reset" then return adminResetRanks(userId) end
	return false
end
adminUpgrades.Parent = ReplicatedStorage

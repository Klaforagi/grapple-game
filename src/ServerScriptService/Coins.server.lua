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

local function publishCollection(player, data)
	local owned = type(data) == "table" and data.cosmetics
	if type(owned) == "table" then
		local catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
		catalog.NormalizeCosmetics(owned)
		local publish = {}
		for id, value in pairs(owned) do
			if type(id) == "string" then
				local safeId = string.gsub(id, "%s+", "")
				if #safeId <= 100 and string.match(safeId, "^[%w_%.%-%/]+$") and catalog.ById[safeId] then
					local copies = catalog.Quantity(value)
					publish[safeId] = math.max(publish[safeId] or 0, copies)
				end
			end
		end
		for id, copies in pairs(publish) do player:SetAttribute("Owned_" .. id, copies) end
	end
	player:SetAttribute("CollectionLoaded", true)
end

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
				publishCollection(player, data)
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

-- A developer-product receipt adds the same amount to held coins and lifetime
-- earned. The purchase id stays on the record so a retried receipt does not pay
-- twice. Unsaved minutes stay in state.earned, so the live balance is the stored
-- total minus that checkpoint, plus the session total.
local function grantCoins(userId, amount, purchaseId)
	if type(userId) ~= "number" or type(purchaseId) ~= "string" or purchaseId == "" or #purchaseId > 100 then
		return false
	end
	amount = tonumber(amount)
	if not amount then return false end
	amount = math.floor(amount)
	if amount <= 0 or amount > 100000000 then return false end

	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	local state = player and sessions[player]
	if state and not state.loaded then
		local started = os.clock()
		while sessions[player] == state and not state.loaded and os.clock() - started < 20 do
			task.wait(0.1)
		end
		if sessions[player] ~= state then state = nil end
	end
	local locked = state
	if locked then
		while locked.saving do task.wait() end
		if not player or sessions[player] ~= locked then locked = nil end
	end
	if locked then locked.saving = true end

	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
			if type(record.purchases) ~= "table" then record.purchases = {} end
			if record.purchases[purchaseId] then return record end
			local held, lifetime = heldAndEarned(record)
			record.coins = held + amount
			record.earned = lifetime + amount
			record.purchases[purchaseId] = os.time()
			return record
		end)
	end)

	if locked then
		if ok and type(data) == "table" and locked.loaded and player and sessions[player] == locked then
			local earned = locked.earned
			local coins = math.floor(tonumber(data.coins) or 0)
			local lifetime = math.floor(tonumber(data.earned) or 0)
			locked.base = coins - locked.saved
			locked.lifetime = math.max(locked.lifetime or 0, lifetime + earned - locked.saved)
			player:SetAttribute("Coins", locked.base + earned)
			publishEarned(player, locked.lifetime)
			queueRank(player.UserId, locked.lifetime)
		end
		locked.saving = false
	end
	return ok and type(data) == "table"
end

local grant = Instance.new("BindableFunction")
grant.Name = "GrantCoins"
grant.OnInvoke = grantCoins
grant.Parent = ReplicatedStorage

-- Spending and refunds change the held balance only. Lifetime earned, and the
-- ordered leaderboard, stay where they are. Unsaved minutes are written first
-- so a player can spend coins they can already see.
local function changeHeld(userId, delta)
	if type(userId) ~= "number" then return false end
	delta = tonumber(delta)
	if not delta then return false end
	delta = math.floor(delta)
	if delta == 0 or math.abs(delta) > 100000000 then return false end

	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	local state = player and sessions[player]
	if state and not state.loaded then
		local started = os.clock()
		while sessions[player] == state and not state.loaded and os.clock() - started < 20 do
			task.wait(0.1)
		end
		if sessions[player] ~= state then state = nil end
	end
	if not state or not state.loaded or not player or sessions[player] ~= state then return false end
	while state.saving do task.wait() end
	if sessions[player] ~= state then return false end
	if state.earned ~= state.saved then
		save(player, state)
		if state.earned ~= state.saved or sessions[player] ~= state then return false end
	end
	while state.saving do task.wait() end
	if sessions[player] ~= state then return false end
	state.saving = true

	local applied = false
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
			local held, lifetime = heldAndEarned(record)
			if held + delta < 0 then
				applied = false
				return previous
			end
			record.coins = held + delta
			record.earned = lifetime
			applied = true
			return record
		end)
	end)
	if ok and applied and type(data) == "table" and sessions[player] == state then
		state.base = math.floor(tonumber(data.coins) or 0) - state.saved
		player:SetAttribute("Coins", state.base + state.earned)
	else
		applied = false
	end
	state.saving = false
	return ok and applied
end

local function spendCoins(userId, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or amount > 100000000 then return false end
	return changeHeld(userId, -amount)
end

local function refundHeld(userId, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or amount > 100000000 then return false end
	return changeHeld(userId, amount)
end

local spend = Instance.new("BindableFunction")
spend.Name = "SpendCoins"
spend.OnInvoke = spendCoins
spend.Parent = ReplicatedStorage

local refund = Instance.new("BindableFunction")
refund.Name = "RefundHeldCoins"
refund.OnInvoke = refundHeld
refund.Parent = ReplicatedStorage

-- Save the charge and added cosmetic copy in ONE coin record update.
-- An ambiguous network failure retains the request ID for the next attempt.
-- The last receipt makes retries idempotent, including UpdateAsync retries.
local rollCosmetic = Instance.new("BindableFunction")
rollCosmetic.Name = "RollCosmetic"
rollCosmetic.OnInvoke = function(player)
	local state = sessions[player]
	if not state or not state.loaded then return {ok = false, message = "Your collection is still loading."} end
	local catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
	local transaction = require(ReplicatedStorage.Modules:WaitForChild("CosmeticTransaction"))
	while state.saving do task.wait() end
	if sessions[player] ~= state then return {ok = false, message = "Please rejoin to roll."} end
	if state.earned ~= state.saved then
		save(player, state)
		if state.earned ~= state.saved then return {ok = false, message = "Coins could not save. Please try again."} end
	end
	while state.saving do task.wait() end
	if sessions[player] ~= state then return {ok = false, message = "Please rejoin to roll."} end
	state.saving = true
	if not state.pendingRoll then
		local luck = catalog.LuckMultiplier(player)
		state.pendingRoll = {id = HttpService:GenerateGUID(false), itemId = catalog.Roll(Random.new(), luck).Id}
	end
	local request = state.pendingRoll
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. player.UserId, function(previous)
			return transaction.Apply(previous, request, catalog)
		end)
	end)
	local result = {ok = false, message = "Could not confirm the roll. Try again to recover it."}
	if ok then
		state.pendingRoll = nil
		if type(data) == "table" and data.lastCosmeticRoll and data.lastCosmeticRoll.id == request.id then
			local receipt = data.lastCosmeticRoll
			state.base = data.coins - state.saved
			if sessions[player] == state then
				player:SetAttribute("Coins", state.base + state.earned)
				publishCollection(player, data)
			end
			result = {ok = true, itemId = receipt.itemId, duplicate = receipt.duplicate,
				copies = receipt.copies or catalog.Quantity(data.cosmetics and data.cosmetics[receipt.itemId])}
		else
			result = {ok = false, message = "You need " .. catalog.Cost .. " coins to roll."}
		end
	end
	state.saving = false
	return result
end
rollCosmetic.Parent = ReplicatedStorage

-- Selling removes one copy and credits held coins in the same atomic write.
-- It shares the coin lock with rolls, purchases, spending, and periodic saves.
local sellCosmetic = Instance.new("BindableFunction")
sellCosmetic.Name = "SellCosmetic"
sellCosmetic.OnInvoke = function(player, itemId, requestId)
	local state = sessions[player]
	if not state or not state.loaded then return {ok = false, message = "Your collection is still loading."} end
	local catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
	local transaction = require(ReplicatedStorage.Modules:WaitForChild("CosmeticTransaction"))
	local item = catalog.ById[itemId]
	if not item or item.Starter or item.Vip or type(requestId) ~= "string" or #requestId == 0 or #requestId > 64 then
		return {ok = false, message = "That item cannot be sold."}
	end
	while state.saving do task.wait() end
	if sessions[player] ~= state then return {ok = false, message = "Please rejoin to sell."} end
	if state.earned ~= state.saved then
		save(player, state)
		if state.earned ~= state.saved then return {ok = false, message = "Coins could not save. Please try again."} end
	end
	while state.saving do task.wait() end
	if sessions[player] ~= state then return {ok = false, message = "Please rejoin to sell."} end
	state.saving = true
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. player.UserId, function(previous)
			return transaction.Sell(previous, {id = requestId, itemId = itemId}, catalog)
		end)
	end)
	local result = {ok = false, retry = true, message = "Sale not confirmed. Click again to retry."}
	if ok then
		local receipt = type(data) == "table" and data.lastCosmeticSale
		if receipt and receipt.id == requestId and receipt.itemId == itemId then
			state.base = data.coins - state.saved
			if sessions[player] == state then
				-- Stop using the sold skin before publishing the last copy's removal.
				if catalog.Quantity(data.cosmetics[itemId]) == 0 and player:GetAttribute(catalog.Attributes[item.Kind]) == item.Name then
					player:SetAttribute(catalog.Attributes[item.Kind], catalog.Defaults[item.Kind])
				end
				player:SetAttribute("Coins", state.base + state.earned)
				publishCollection(player, data)
			end
			result = {ok = true, itemId = itemId, copies = receipt.copies, price = receipt.price}
		else
			result = {ok = false, message = "You do not own a copy of that item."}
		end
	end
	state.saving = false
	return result
end
sellCosmetic.Parent = ReplicatedStorage

-- Spending never lowers lifetime coins. An admin reset is a separate write:
-- it may zero both balances, and it updates the live session so leaving
-- cannot save the old totals back.
-- Admin gifts add held coins only. Lifetime earned and the ordered board stay put,
-- including when the player is offline and there is no live session to update.
local function adminGrantHeld(userId, amount)
	if type(userId) ~= "number" then return false end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or amount > 100000000 then return false end
	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	if player then return changeHeld(userId, amount) end
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
			local held, lifetime = heldAndEarned(record)
			record.coins = held + amount
			record.earned = lifetime
			return record
		end)
	end)
	return ok and type(data) == "table"
end

local function adminReadCoins(userId)
	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	local state = player and sessions[player]
	if not state or not state.loaded or sessions[player] ~= state then return nil end
	return {coins = state.base + state.earned, earned = state.lifetime or 0}
end

-- Admin cosmetic gifts use the same coin record as rolls, so they survive for
-- offline players and immediately publish as an inventory stack for online ones.
local function adminGrantCosmetic(userId, itemId)
	if type(userId) ~= "number" or type(itemId) ~= "string" then return false end
	local catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
	local item = catalog.ById[itemId]
	if not item or item.Starter or item.Vip then return false end
	local player = Players:GetPlayerByUserId(userId)
	local state = player and sessions[player]
	if state and not state.loaded then
		local started = os.clock()
		while sessions[player] == state and not state.loaded and os.clock() - started < 20 do task.wait(0.1) end
	end
	if player and (not state or sessions[player] ~= state or not state.loaded) then return false end
	if state then
		while state.saving do task.wait() end
		if sessions[player] ~= state then return false end
		if state.earned ~= state.saved then
			save(player, state)
			if state.earned ~= state.saved then return false end
		end
		while state.saving do task.wait() end
		if sessions[player] ~= state then return false end
		state.saving = true
	end
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
			record.cosmetics = type(record.cosmetics) == "table" and record.cosmetics or {}
			catalog.NormalizeCosmetics(record.cosmetics)
			record.cosmetics[item.Id] = catalog.Quantity(record.cosmetics[item.Id]) + 1
			return record
		end)
	end)
	if state then
		if ok and type(data) == "table" and sessions[player] == state then publishCollection(player, data) end
		state.saving = false
	end
	return ok and type(data) == "table"
end

local function adminResetCoins(userId)
	if type(userId) ~= "number" then return false end
	local lookup = Players.GetPlayerByUserId
	local player = type(lookup) == "function" and lookup(Players, userId) or nil
	local state = player and sessions[player]
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
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
			record.coins = 0
			record.earned = 0
			if state then
				record.sessions = record.sessions or {}
				record.sessions[state.id] = {earned = 0, at = os.time()}
			end
			return record
		end)
	end)
	if state then
		if ok and type(data) == "table" and state.loaded and player and sessions[player] == state then
			state.started = os.clock()
			state.earned = 0
			state.saved = 0
			state.base = 0
			state.lifetime = 0
			player:SetAttribute("Coins", 0)
			player:SetAttribute("CoinsEarned", nil)
		end
		state.saving = false
	end
	if ok then forceRank(userId, 0) requestRefresh() end
	return ok and type(data) == "table"
end

local adminCoins = Instance.new("BindableFunction")
adminCoins.Name = "AdminCoins"
adminCoins.OnInvoke = function(action, userId, amount)
	if action == "read" then return adminReadCoins(userId) end
	if action == "reset" then return adminResetCoins(userId) end
	if action == "grant" then return adminGrantHeld(userId, amount) end
	return false
end
adminCoins.Parent = ReplicatedStorage

local adminCosmetics = Instance.new("BindableFunction")
adminCosmetics.Name = "AdminCosmetics"
adminCosmetics.OnInvoke = function(action, userId, itemId)
	if action == "grant" then return adminGrantCosmetic(userId, itemId) end
	return false
end
adminCosmetics.Parent = ReplicatedStorage

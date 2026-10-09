local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local store = DataStoreService:GetDataStore("GrappleCoins_v1")
local sessions = {}

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
				record.coins = (record.coins or 0) + math.max(0, earned - alreadySaved)
				record.sessions[state.id] = {earned = earned, at = os.time()}
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
		player:SetAttribute("Coins", state.base + state.earned)
	else
		warn("[Coins] Save failed for " .. player.Name .. ": " .. tostring(data))
	end
	state.saving = false
end

local function joined(player)
	if sessions[player] then return end
	local state = {id = HttpService:GenerateGUID(false), started = os.clock(), earned = 0, saved = 0, base = 0}
	sessions[player] = state
	player:SetAttribute("Coins", 0)
	task.spawn(function()
		while sessions[player] == state and not state.loaded do
			local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
			if ok then
				state.base = type(data) == "table" and (data.coins or 0) or 0
				state.loaded = true
				player:SetAttribute("Coins", state.base + state.earned)
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
			state.earned = earned
			player:SetAttribute("Coins", state.base + earned)
			if state.loaded and not state.saving then task.spawn(save, player, state) end
		end
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

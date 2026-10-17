-- Seven-day login streak using the same 12:00 UTC boundary as playtime rewards.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Daily = require(ReplicatedStorage.Modules:WaitForChild("DailyRewards"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local store
pcall(function() store = DataStoreService:GetDataStore("GrappleDailyRewards_v1") end)

local sessions = {}

local function publish(player, session)
	local day = Daily.DayKey(os.time())
	local streak = session.lastClaimDay >= day - 1 and session.streak or 0
	player:SetAttribute("DailyDay", day)
	player:SetAttribute("DailyStreak", streak)
	player:SetAttribute("DailyLastClaim", session.lastClaimDay)
	player:SetAttribute("DailyLoaded", true)
end

local function save(player, session)
	if not store or not session or not session.loaded then return end
	local lastClaimDay, streak = session.lastClaimDay, session.streak
	local ok = pcall(function()
		store:UpdateAsync("player_" .. player.UserId, function(previous)
			local record = type(previous) == "table" and previous or {}
			local savedDay = tonumber(record.lastClaimDay)
			if savedDay and savedDay >= lastClaimDay then return record end
			record.lastClaimDay = lastClaimDay
			record.streak = streak
			return record
		end)
	end)
	if not ok then warn("[DailyRewards] Could not save " .. player.Name) end
end

local function load(player)
	local data, ok
	repeat
		if not store then ok = true break end
		ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
		if not ok then task.wait(5) end
	until ok or player.Parent ~= Players
	if player.Parent ~= Players then return end
	local lastClaimDay = type(data) == "table" and math.floor(tonumber(data.lastClaimDay) or -1) or -1
	local streak = type(data) == "table" and math.floor(tonumber(data.streak) or 0) or 0
	local session = {lastClaimDay = lastClaimDay, streak = math.clamp(streak, 0, #Daily.Coins), loaded = true, claiming = false}
	sessions[player] = session
	publish(player, session)
end

local function claim(player)
	local session = sessions[player]
	if not session or not session.loaded or session.claiming then return end
	local day = Daily.DayKey(os.time())
	local index, alreadyClaimed = Daily.Current(day, session.lastClaimDay, session.streak)
	if alreadyClaimed then return end
	session.claiming = true
	local amount = Daily.Coins[index] * (player:GetAttribute("TestPass_2xCoins") == true and 2 or 1)
	local grant = ReplicatedStorage:FindFirstChild("GrantCoins")
	local paid = false
	if grant and type(grant.Invoke) == "function" then
		local ok, result = pcall(function()
			return grant:Invoke(player.UserId, amount, "daily_" .. day, Daily.Tickets[index])
		end)
		paid = ok and result == true
	end
	if paid and sessions[player] == session then
		session.lastClaimDay = day
		session.streak = index
		publish(player, session)
		save(player, session)
		if player.Parent == Players then Remotes.CoinGain:FireClient(player, amount) end
	end
	session.claiming = false
end

Remotes.ClaimDaily.OnServerEvent:Connect(claim)
Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	if session then save(player, session) end
	sessions[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do save(player, sessions[player]) end
end)

task.spawn(function()
	while true do
		task.wait(1)
		local day = Daily.DayKey(os.time())
		for player, session in pairs(sessions) do
			if player.Parent == Players and player:GetAttribute("DailyDay") ~= day then
				publish(player, session)
			end
		end
	end
end)

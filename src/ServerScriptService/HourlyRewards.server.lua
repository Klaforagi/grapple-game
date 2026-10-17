-- Playtime rewards for the current 12:00 UTC day. Leaving keeps the saved seconds.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Hourly = require(ReplicatedStorage.Modules:WaitForChild("HourlyRewards"))
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))

local store
pcall(function()
	store = DataStoreService:GetDataStore("GrappleHourly_v1")
end)

local sessions = {}

local function publish(player, session)
	player:SetAttribute("HourlyDay", session.day)
	player:SetAttribute("HourlySeconds", math.floor(session.seconds))
	player:SetAttribute("HourlyClaimed", session.claimed)
end

local function pay(player, day, index, amount, tickets)
	local grant = ReplicatedStorage:FindFirstChild("GrantCoins")
	if not grant or type(grant.Invoke) ~= "function" then return false end
	local purchaseId = string.format("hourly_%d_%d", day, index)
	local ok, paid = pcall(function()
		return grant:Invoke(player.UserId, amount, purchaseId, tickets)
	end)
	return ok and paid == true
end

local function claim(player, index)
	local session = sessions[player]
	if not session or not session.loaded or type(index) ~= "number" then return end
	index = math.floor(index)
	local tier = Hourly.Tiers[index]
	if not tier or session.seconds < tier.minutes * 60 or Hourly.Has(session.claimed, index) then return end
	-- Keep the tier labels at their base value; only the actual payout and gain
	-- popup reflect the 2x Coins pass.
	local amount = tier.coins * (player:GetAttribute("TestPass_2xCoins") == true and 2 or 1)
	if not pay(player, session.day, index, amount, tier.tickets or 0) then return end
	session.claimed = Hourly.Mark(session.claimed, index)
	session.dirty = true
	session.saveAt = 0
	publish(player, session)
	if Remotes.CoinGain then Remotes.CoinGain:FireClient(player, amount) end
end

local function save(player)
	local session = sessions[player]
	if not session or not session.loaded or not store then return end
	local snapshot = {day = session.day, seconds = math.floor(session.seconds), claimed = session.claimed}
	local key = "player_" .. player.UserId
	local ok = pcall(function()
		store:UpdateAsync(key, function(previous)
			local record = type(previous) == "table" and previous or {}
			record.day = snapshot.day
			record.seconds = snapshot.seconds
			record.claimed = snapshot.claimed
			return record
		end)
	end)
	if not ok then warn("[Hourly] Could not save " .. player.Name) end
end

local function load(player)
	local data
	local ok = false
	repeat
		if not store then
			ok, data = true, nil
			break
		end
		ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
		if not ok then task.wait(5) end
	until ok or player.Parent ~= Players
	if player.Parent ~= Players then return end
	local day = Hourly.DayKey(os.time())
	local seconds, claimed = 0, 0
	if type(data) == "table" and tonumber(data.day) == day then
		seconds = math.clamp(math.floor(tonumber(data.seconds) or 0), 0, Hourly.Cap())
		claimed = math.max(0, math.floor(tonumber(data.claimed) or 0))
	end
	local session = {day = day, seconds = seconds, claimed = claimed, loaded = true, saveAt = os.clock() + 20, dirty = false}
	sessions[player] = session
	publish(player, session)
end

Remotes.ClaimHourly.OnServerEvent:Connect(claim)

Players.PlayerAdded:Connect(function(player)
	task.spawn(load, player)
end)
Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(load, player)
end
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do save(player) end
end)

RunService.Heartbeat:Connect(function(dt)
	if dt > 5 then dt = 5 end
	if dt < 0 then dt = 0 end
	local day = Hourly.DayKey(os.time())
	for player, session in pairs(sessions) do
		if session.loaded and player.Parent == Players then
			if day ~= session.day then
				session.day = day
				session.seconds = 0
				session.claimed = 0
				session.dirty = true
			end
			local before = math.floor(session.seconds)
			session.seconds = math.min(Hourly.Cap(), session.seconds + dt)
			if math.floor(session.seconds) ~= before then
				session.dirty = true
				publish(player, session)
			end
			if session.dirty and os.clock() >= session.saveAt then
				session.dirty = false
				session.saveAt = os.clock() + 20
				task.spawn(save, player)
			end
		end
	end
end)

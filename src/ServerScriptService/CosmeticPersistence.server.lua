local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local store = DataStoreService:GetDataStore("GrappleCosmetics_v1")
local keys = {"GrappleGunColor", "GrappleRopeColor", "BombColor"}

local function load(player)
	local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
	if ok and type(data) == "table" then
		for _, key in ipairs(keys) do
			if type(data[key]) == "string" then player:SetAttribute(key, data[key]) end
		end
	elseif not ok then
		warn("[Cosmetics] Could not load " .. player.Name)
	end
end

local function save(player)
	local data = {}
	for _, key in ipairs(keys) do data[key] = player:GetAttribute(key) end
	local ok = pcall(function() store:SetAsync("player_" .. player.UserId, data) end)
	if not ok then warn("[Cosmetics] Could not save " .. player.Name) end
end

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
Players.PlayerRemoving:Connect(save)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))

local store = DataStoreService:GetDataStore("GrappleCosmetics_v1")
local colorKeys = {"GrappleGunColor", "GrappleRopeColor", "BombColor"}
local settingDefaults = {
	LocalClockTime = Lighting.ClockTime,
	ShadowsEnabled = Lighting.GlobalShadows,
	MusicVolume = 1,
}

local function validSetting(key, value)
	if key == "LocalClockTime" then
		return typeof(value) == "number" and value == value and value >= 0 and value <= 24
	elseif key == "ShadowsEnabled" then
		return typeof(value) == "boolean"
	elseif key == "MusicVolume" then
		return typeof(value) == "number" and value == value and value >= 0 and value <= 1
	end
	return false
end

local function load(player)
	local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
	if ok and type(data) == "table" then
		if data.BombColor == "Teal" then data.BombColor = "Mint" end
		for _, key in ipairs(colorKeys) do
			if key == "BombColor" and data[key] == "Lime" then data[key] = "Green" end
			if type(data[key]) == "string" then player:SetAttribute(key, data[key]) end
		end
		for key, default in pairs(settingDefaults) do
			local value = data[key]
			player:SetAttribute(key, validSetting(key, value) and value or default)
		end
	elseif not ok then
		warn("[Cosmetics] Could not load " .. player.Name)
	end
	for key, default in pairs(settingDefaults) do
		if player:GetAttribute(key) == nil then player:SetAttribute(key, default) end
	end
	player:SetAttribute("SettingsLoaded", true)
end

local function save(player)
	local data = {}
	for _, key in ipairs(colorKeys) do data[key] = player:GetAttribute(key) end
	for key, default in pairs(settingDefaults) do
		local value = player:GetAttribute(key)
		data[key] = validSetting(key, value) and value or default
	end
	local ok = pcall(function() store:SetAsync("player_" .. player.UserId, data) end)
	if not ok then warn("[PlayerSettings] Could not save " .. player.Name) end
end

Remotes.SetPlayerSetting.OnServerEvent:Connect(function(player, key, value)
	if type(key) ~= "string" or not validSetting(key, value) then return end
	player:SetAttribute(key, value)
end)

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
Players.PlayerRemoving:Connect(save)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do save(player) end
end)

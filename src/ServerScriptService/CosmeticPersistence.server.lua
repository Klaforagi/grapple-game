local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
local AdminList = require(script.Parent:WaitForChild("AdminList"))
local loaded, saving = {}, {}

local store = DataStoreService:GetDataStore("GrappleCosmetics_v1")
local colorKeys = {"GrappleGunColor", "GrappleRopeColor", "BombColor"}
local settingDefaults = {
	LocalClockTime = Lighting.ClockTime,
	ShadowsEnabled = Lighting.GlobalShadows,
	MusicVolume = 1,
	MusicMuted = false,
	EffectsVolume = 1,
}

local function validSetting(key, value)
	if key == "LocalClockTime" then
		return typeof(value) == "number" and value == value and value >= 0 and value <= 24
	elseif key == "ShadowsEnabled" then
		return typeof(value) == "boolean"
	elseif key == "MusicVolume" or key == "EffectsVolume" then
		return typeof(value) == "number" and value == value and value >= 0 and value <= 1
	elseif key == "MusicMuted" then
		return typeof(value) == "boolean"
	end
	return false
end

local function load(player)
	for kind, name in pairs(Catalog.Defaults) do player:SetAttribute(Catalog.Attributes[kind], name) end
	player:SetAttribute("Admin", AdminList.IsAdmin(player.UserId))
	local ok, data
	repeat
		ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
		if not ok then task.wait(10) end
	until ok or player.Parent ~= Players
	if player.Parent ~= Players then return end
	while player.Parent == Players and player:GetAttribute("CollectionLoaded") ~= true do task.wait(0.1) end
	if player.Parent ~= Players then return end
	if ok and type(data) == "table" then
		if data.BombColor == "Teal" then data.BombColor = "Mint" end
		if data.GrappleGunColor == "Teal" then data.GrappleGunColor = "Mint" end
		if data.GrappleRopeColor == "Teal" then data.GrappleRopeColor = "Mint" end
		if data.GrappleRopeColor == "Neon Lime" then data.GrappleRopeColor = "Neon Green" end
		for kind, key in pairs(Catalog.Attributes) do
			if key == "BombColor" and data[key] == "Lime" then data[key] = "Green" end
			if type(data[key]) == "string" and Catalog.Owns(player, kind, data[key]) then
				player:SetAttribute(key, data[key])
			end
		end
		for key, default in pairs(settingDefaults) do
			local value = data[key]
			if not validSetting(key, value) then value = default end
			player:SetAttribute(key, value)
		end
	elseif not ok then
		warn("[Cosmetics] Could not load " .. player.Name)
	end
	for key, default in pairs(settingDefaults) do
		if player:GetAttribute(key) == nil then player:SetAttribute(key, default) end
	end
	player:SetAttribute("SettingsLoaded", true)
	loaded[player] = true
end

local function save(player)
	while saving[player] do task.wait() end
	if not loaded[player] then return end
	saving[player] = true
	local data = {}
	for _, key in ipairs(colorKeys) do data[key] = player:GetAttribute(key) end
	for key, default in pairs(settingDefaults) do
		local value = player:GetAttribute(key)
		if not validSetting(key, value) then value = default end
		data[key] = value
	end
	local ok = pcall(function()
		store:UpdateAsync("player_" .. player.UserId, function(previous)
			local record = type(previous) == "table" and previous or {}
			for key, value in pairs(data) do record[key] = value end
			return record
		end)
	end)
	if not ok then warn("[PlayerSettings] Could not save " .. player.Name) end
	saving[player] = nil
end

Remotes.SetPlayerSetting.OnServerEvent:Connect(function(player, key, value)
	if type(key) ~= "string" or not validSetting(key, value) then return end
	player:SetAttribute(key, value)
end)

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
Players.PlayerRemoving:Connect(function(player) save(player) loaded[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do save(player) end
end)
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do task.spawn(save, player) end
	end
end)

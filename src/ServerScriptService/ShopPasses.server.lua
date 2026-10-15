-- Temporary test-pass toggles persist between sessions until real purchase
-- prompts replace ToggleTestPass.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Catalog = require(ReplicatedStorage.Modules:WaitForChild("ShopCatalog"))

local allowed = {}
for _, pass in ipairs(Catalog.Passes) do
	allowed[pass.name] = Catalog.TestAttribute(pass.name)
end

local store = DataStoreService:GetDataStore("GrappleTestPasses_v1")
local states = {}

local function load(player)
	if states[player] then return states[player] end
	local state = {loaded = false, saving = false, values = {}}
	states[player] = state
	local ok, data = pcall(function() return store:GetAsync("player_" .. player.UserId) end)
	if ok and type(data) == "table" then
		for _, key in pairs(allowed) do state.values[key] = data[key] == true end
	end
	if player.Parent == Players then
		for _, key in pairs(allowed) do player:SetAttribute(key, state.values[key] == true) end
	end
	state.loaded = true
	return state
end

local function beginLoad(player)
	if states[player] then return end
	task.spawn(load, player)
end

Remotes.ToggleTestPass.OnServerEvent:Connect(function(player, name)
	local key = type(name) == "string" and allowed[name]
	if not key then return end
	local state = states[player] or load(player)
	while not state.loaded or state.saving do task.wait() end
	if states[player] ~= state or player.Parent ~= Players then return end
	local enabled = state.values[key] ~= true
	state.saving = true
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. player.UserId, function(previous)
			local record = type(previous) == "table" and previous or {}
			record[key] = enabled
			return record
		end)
	end)
	if ok and type(data) == "table" and states[player] == state and player.Parent == Players then
		state.values[key] = enabled
		player:SetAttribute(key, enabled)
	end
	state.saving = false
end)

Players.PlayerAdded:Connect(beginLoad)
Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do beginLoad(player) end

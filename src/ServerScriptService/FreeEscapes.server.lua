-- Daily escapes are tracked as uses, so a new day always resets to the current pass cap.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local store = DataStoreService:GetDataStore("GrappleFreeEscapes_v1")
local states = {}

local function currentDay()
	return math.floor((os.time() - 12 * 60 * 60) / 86400)
end

local function escapeCap(player)
	return player:GetAttribute("TestPass_VIP") == true and 3 or 1
end

local function publish(player, state)
	if player.Parent ~= Players then return end
	local day = currentDay()
	if state.day ~= day then
		state.day = day
		state.used = 0
	end
	player:SetAttribute("FreeEscapes", math.max(0, escapeCap(player) - state.used))
end

local function load(player)
	if states[player] then return states[player] end
	local day = currentDay()
	local state = {day = day, used = 0, loading = true, using = false}
	states[player] = state
	local ok, data = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if ok and type(data) == "table" and data.day == day then
		state.used = math.max(0, math.floor(tonumber(data.used) or 0))
	end
	state.loading = false
	publish(player, state)
	return state
end

local function useFreeEscape(player)
	if not player or player.Parent ~= Players then return false end
	local state = states[player] or load(player)
	while state.loading or state.using do task.wait() end
	if states[player] ~= state or player.Parent ~= Players then return false end
	publish(player, state)
	if state.used >= escapeCap(player) then return false end

	state.using = true
	local day = currentDay()
	local requestId = HttpService:GenerateGUID(false)
	local ok, data = pcall(function()
		return store:UpdateAsync("player_" .. player.UserId, function(previous)
			local record = type(previous) == "table" and previous or {}
			local used = math.max(0, math.floor(tonumber(record.used) or 0))
			if record.day ~= day then used = 0 end
			if record.requestId == requestId then return record end
			if used >= escapeCap(player) then return nil end
			record.day = day
			record.used = used + 1
			record.requestId = requestId
			return record
		end)
	end)
	state.using = false
	if ok and type(data) == "table" and data.requestId == requestId then
		state.day = day
		state.used = math.max(0, math.floor(tonumber(data.used) or 0))
		publish(player, state)
		return true
	end
	publish(player, state)
	return false
end

local remote = Instance.new("BindableFunction")
remote.Name = "UseFreeEscape"
remote.OnInvoke = useFreeEscape
remote.Parent = ReplicatedStorage

local function watch(player)
	task.spawn(load, player)
	player:GetAttributeChangedSignal("TestPass_VIP"):Connect(function()
		local state = states[player]
		if state then publish(player, state) end
	end)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end

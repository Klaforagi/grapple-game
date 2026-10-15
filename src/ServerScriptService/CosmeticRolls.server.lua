local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PolicyService = game:GetService("PolicyService")
local Catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
local roll = ReplicatedStorage:WaitForChild("RollCosmetic")
local remote = Instance.new("RemoteFunction")
remote.Name = "RequestCosmeticRoll"
local busy, nextRoll = {}, {}
local lastResult = {}

local function checkPolicy(player)
	player:SetAttribute("CosmeticRollAllowed", false)
	player:SetAttribute("CosmeticRollPolicy", "Checking roll availability...")
	while player.Parent == Players do
		local ok, policy = pcall(function() return PolicyService:GetPolicyInfoForPlayerAsync(player) end)
		if player.Parent ~= Players then return end
		if ok and type(policy) == "table" and type(policy.ArePaidRandomItemsRestricted) == "boolean" then
			local allowed = not policy.ArePaidRandomItemsRestricted
			player:SetAttribute("CosmeticRollAllowed", allowed)
			player:SetAttribute("CosmeticRollPolicy", allowed and "" or "Coin rolls are unavailable for your account.")
			return
		end
		player:SetAttribute("CosmeticRollPolicy", "Roll availability could not load. Retrying...")
		task.wait(15)
	end
end

remote.OnServerInvoke = function(player, zone, requestId)
	if type(requestId) ~= "string" or #requestId == 0 or #requestId > 64 then
		return {ok = false, message = "Invalid roll request."}
	end
	if player:GetAttribute("CosmeticRollAllowed") ~= true then
		return {ok = false, message = player:GetAttribute("CosmeticRollPolicy") or "Rolls are unavailable."}
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if typeof(zone) ~= "Instance" or not Catalog.IsStationPart(zone) or not root or not humanoid
		or humanoid.Health <= 0 or not Catalog.Inside(zone, root.Position, Catalog.ServerPadding) then
		return {ok = false, message = "Stand in the roll zone first."}
	end
	-- A client retry after a lost response returns the already paid-for result.
	local cached = lastResult[player]
	if cached and cached.id == requestId then return cached.result end
	if busy[player] or os.clock() < (nextRoll[player] or 0) then
		return {ok = false, message = "Let this roll finish first!"}
	end
	busy[player] = true
	nextRoll[player] = os.clock() + Catalog.Cooldown
	local ok, result = pcall(function() return roll:Invoke(player) end)
	busy[player] = nil
	if not ok then
		warn("[CosmeticRolls] " .. tostring(result))
		return {ok = false, message = "The roll could not finish. Please try again."}
	end
	if result.ok and player.Parent == Players then lastResult[player] = {id = requestId, result = result} end
	return result
end
remote.Parent = ReplicatedStorage
Players.PlayerAdded:Connect(function(player) task.spawn(checkPolicy, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(checkPolicy, player) end
Players.PlayerRemoving:Connect(function(player) busy[player], nextRoll[player], lastResult[player] = nil, nil, nil end)

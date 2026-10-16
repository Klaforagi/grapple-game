local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage.Modules:WaitForChild("CosmeticCatalog"))
local sell = ReplicatedStorage:WaitForChild("SellCosmetic")
local remote = Instance.new("RemoteFunction")
remote.Name = "RequestCosmeticSale"
local busy, nextSale, pending, lastResult = {}, {}, {}, {}

remote.OnServerInvoke = function(player, itemId, requestId)
	if type(itemId) ~= "string" or type(requestId) ~= "string" or #requestId == 0 or #requestId > 64 then
		return {ok = false, message = "Invalid sale request."}
	end
	local item = Catalog.ById[itemId]
	if not item or item.Starter or item.Vip then return {ok = false, message = "That item cannot be sold."} end
	local cached = lastResult[player]
	if cached and cached.id == requestId and cached.itemId == itemId then return cached.result end
	local unresolved = pending[player]
	if unresolved and (unresolved.id ~= requestId or unresolved.itemId ~= itemId) then
		return {ok = false, message = "Retry your previous sale first."}
	end
	if busy[player] or os.clock() < (nextSale[player] or 0) then
		return {ok = false, retry = true, message = "Please wait for your sale to finish."}
	end
	busy[player] = true
	nextSale[player] = os.clock() + 0.5
	pending[player] = {id = requestId, itemId = itemId}
	local ok, result = pcall(function() return sell:Invoke(player, itemId, requestId) end)
	busy[player] = nil
	if not ok then return {ok = false, retry = true, message = "Sale not confirmed. Click again to retry."} end
	if player.Parent == Players then
		if not result.retry then pending[player] = nil end
		if result.ok then lastResult[player] = {id = requestId, itemId = itemId, result = result} end
	end
	return result
end
remote.Parent = ReplicatedStorage
Players.PlayerRemoving:Connect(function(player)
	busy[player], nextSale[player], pending[player], lastResult[player] = nil, nil, nil, nil
end)

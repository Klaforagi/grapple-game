-- Track purchases made through this experience for the admin player profile.
-- Developer products use their receipt's actual CurrencySpent. Passes have no
-- receipt, so the server records their current Roblox price when bought here.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local store = DataStoreService:GetDataStore("GrappleRobuxSpent_v1")

local function recordSpent(userId, purchaseKey, amount)
	if type(userId) ~= "number" or userId <= 0 or type(purchaseKey) ~= "string" or purchaseKey == ""
		or type(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false
	end
	amount = math.floor(amount)
	local ok, result = pcall(function()
		return store:UpdateAsync("player_" .. userId, function(previous)
			local record = type(previous) == "table" and previous or {}
			record.purchases = type(record.purchases) == "table" and record.purchases or {}
			if record.purchases[purchaseKey] ~= nil then return record end
			record.spent = math.max(0, math.floor(tonumber(record.spent) or 0)) + amount
			record.purchases[purchaseKey] = amount
			return record
		end)
	end)
	return ok and type(result) == "table"
end

local recorder = Instance.new("BindableFunction")
recorder.Name = "RecordRobuxSpent"
recorder.OnInvoke = recordSpent
recorder.Parent = ReplicatedStorage

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased ~= true or not player or type(passId) ~= "number" or passId <= 0 then return end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(passId, Enum.InfoType.GamePass)
			end)
			local price = ok and type(info) == "table" and info.PriceInRobux
			if type(price) == "number" and recordSpent(player.UserId, "pass_" .. passId, price) then return end
			if attempt < 3 then task.wait(2) end
		end
		warn("Could not record Robux spent on pass", passId, "for", player.UserId)
	end)
end)

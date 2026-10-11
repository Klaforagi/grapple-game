-- Turns a developer-product receipt into coins. Gamepasses are not granted here.
-- This is the only ProcessReceipt handler. An unknown product stays unprocessed.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Modules:WaitForChild("ShopCatalog"))
local grant = ReplicatedStorage:WaitForChild("GrantCoins")

local packs = {}
for _, pack in ipairs(Catalog.Coins) do
	if type(pack.id) == "number" and pack.id > 0 and type(pack.amount) == "number" and pack.amount > 0 then
		packs[pack.id] = math.floor(pack.amount)
	end
end

MarketplaceService.ProcessReceipt = function(receipt)
	local amount = type(receipt) == "table" and packs[receipt.ProductId] or nil
	if not amount or type(receipt.PurchaseId) ~= "string" or type(receipt.PlayerId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(function()
		return grant:Invoke(receipt.PlayerId, amount, receipt.PurchaseId)
	end)
	if ok and granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

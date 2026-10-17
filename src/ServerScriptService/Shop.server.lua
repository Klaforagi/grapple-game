-- Turns a developer-product receipt into coins or one upgrade rank.
-- Gamepasses are not granted here.
-- This is the only ProcessReceipt handler. An unknown product stays unprocessed.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Modules:WaitForChild("ShopCatalog"))
local Upgrades = require(ReplicatedStorage.Modules:WaitForChild("UpgradeCatalog"))
local GrappleConfig = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local grant = ReplicatedStorage:WaitForChild("GrantCoins")
local grantUpgrade = ReplicatedStorage:WaitForChild("GrantUpgradeRobux")
local grantEscape = ReplicatedStorage:WaitForChild("GrantEscapeRobux")
local grantEscapeKill = ReplicatedStorage:WaitForChild("GrantEscapeKillRobux")
local recordSpent = ReplicatedStorage:WaitForChild("RecordRobuxSpent")

local packs = {}
for _, pack in ipairs(Catalog.Coins) do
	if type(pack.id) == "number" and pack.id > 0 and type(pack.amount) == "number" and pack.amount > 0 then
		packs[pack.id] = math.floor(pack.amount)
	end
end

local function finishReceipt(receipt, granted)
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- Receipt IDs make a retry safe even if granting succeeded but saving the
	-- spending total failed. CurrencySpent is the amount Roblox actually charged.
	local ok, recorded = pcall(function()
		return recordSpent:Invoke(receipt.PlayerId, "product_" .. receipt.PurchaseId, receipt.CurrencySpent)
	end)
	return ok and recorded == true and Enum.ProductPurchaseDecision.PurchaseGranted
		or Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = function(receipt)
	if type(receipt) ~= "table" or type(receipt.PurchaseId) ~= "string" or type(receipt.PlayerId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local upgradeId = Upgrades.RobuxProductId
	if type(upgradeId) == "number" and upgradeId > 0 and receipt.ProductId == upgradeId then
		local ok, granted = pcall(function()
			return grantUpgrade:Invoke(receipt.PlayerId, receipt.PurchaseId)
		end)
		return finishReceipt(receipt, ok and granted == true)
	end
	local escapeId = GrappleConfig.escapeRobuxProductId
	if type(escapeId) == "number" and escapeId > 0 and receipt.ProductId == escapeId then
		local ok, granted = pcall(function()
			return grantEscape:Invoke(receipt.PlayerId, receipt.PurchaseId)
		end)
		return finishReceipt(receipt, ok and granted == true)
	end
	local escapeKillId = GrappleConfig.escapeKillRobuxProductId
	if type(escapeKillId) == "number" and escapeKillId > 0 and receipt.ProductId == escapeKillId then
		local ok, granted = pcall(function()
			return grantEscapeKill:Invoke(receipt.PlayerId, receipt.PurchaseId)
		end)
		return finishReceipt(receipt, ok and granted == true)
	end
	local amount = packs[receipt.ProductId]
	if not amount then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(function()
		return grant:Invoke(receipt.PlayerId, amount, receipt.PurchaseId)
	end)
	return finishReceipt(receipt, ok and granted == true)
end

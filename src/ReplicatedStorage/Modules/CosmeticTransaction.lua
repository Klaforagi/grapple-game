-- Pure atomic transform for GrappleCoins_v1. No yielding and no RNG here:
-- UpdateAsync can rerun this callback; a request must always keep its item/id.
local Transaction = {}
function Transaction.Apply(previous, request, catalog)
	local record = type(previous) == "table" and previous or {coins = 0, earned = 0}
	if record.lastCosmeticRoll and record.lastCosmeticRoll.id == request.id then return record end
	local held = math.max(0, math.floor(tonumber(record.coins) or 0))
	if held < catalog.Cost then return nil end
	local item = catalog.ById[request.itemId]
	if not item or item.Starter then return nil end
	record.cosmetics = type(record.cosmetics) == "table" and record.cosmetics or {}
	local copies = catalog.Quantity(record.cosmetics[item.Id]) + 1
	record.earned = tonumber(record.earned) or held
	record.coins = held - catalog.Cost
	record.cosmetics[item.Id] = copies
	record.lastCosmeticRoll = {id = request.id, itemId = item.Id, duplicate = copies > 1, copies = copies}
	return record
end

function Transaction.Sell(previous, request, catalog)
	if type(previous) ~= "table" then return nil end
	if previous.lastCosmeticSale and previous.lastCosmeticSale.id == request.id then
		return previous.lastCosmeticSale.itemId == request.itemId and previous or nil
	end
	local item = catalog.ById[request.itemId]
	if not item or item.Starter then return nil end
	local owned = previous.cosmetics
	local copies = type(owned) == "table" and catalog.Quantity(owned[item.Id]) or 0
	local price = catalog.SellPrices[item.Rarity]
	if copies < 1 or not price then return nil end
	local held = math.max(0, math.floor(tonumber(previous.coins) or 0))
	previous.earned = tonumber(previous.earned) or held
	previous.coins = held + price
	owned[item.Id] = copies - 1
	previous.lastCosmeticSale = {id = request.id, itemId = item.Id, copies = copies - 1, price = price}
	return previous
end
return Transaction

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
	local duplicate = record.cosmetics[item.Id] == true
	local refund = duplicate and catalog.Rarity(item.Rarity).Refund or 0
	record.earned = tonumber(record.earned) or held
	record.coins = held - catalog.Cost + refund
	record.cosmetics[item.Id] = true
	record.lastCosmeticRoll = {id = request.id, itemId = item.Id, duplicate = duplicate, refund = refund}
	return record
end
return Transaction

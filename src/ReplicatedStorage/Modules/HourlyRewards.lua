-- Daily playtime rewards. The day rolls at 12:00 UTC, not midnight.
local Hourly = {}

Hourly.ResetHourUtc = 12
Hourly.Tiers = {
	{minutes = 5, coins = 10},
	{minutes = 15, coins = 15},
	{minutes = 30, coins = 25},
	{minutes = 45, coins = 35},
	{minutes = 60, coins = 65, tickets = 1},
}

function Hourly.Cap()
	return Hourly.Tiers[#Hourly.Tiers].minutes * 60
end

function Hourly.DayKey(now)
	return math.floor((now - Hourly.ResetHourUtc * 3600) / 86400)
end

function Hourly.Has(claimed, index)
	return bit32.band(claimed, bit32.lshift(1, index - 1)) ~= 0
end

function Hourly.Mark(claimed, index)
	return bit32.bor(claimed, bit32.lshift(1, index - 1))
end

-- Tier indexes whose time has been reached and which have not been paid yet.
function Hourly.Due(seconds, claimed)
	local due = {}
	for index, tier in ipairs(Hourly.Tiers) do
		if seconds >= tier.minutes * 60 and not Hourly.Has(claimed, index) then
			table.insert(due, index)
		end
	end
	return due
end

return Hourly

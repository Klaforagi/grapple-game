local Hourly = require(script.Parent:WaitForChild("HourlyRewards"))

local Daily = {}
Daily.Coins = {25, 35, 50, 75, 100, 150, 250}
Daily.Tickets = {1, 1, 1, 1, 1, 1, 5}
Daily.DayKey = Hourly.DayKey
Daily.ResetHourUtc = Hourly.ResetHourUtc

function Daily.Current(day, lastClaimDay, streak)
	streak = math.clamp(math.floor(tonumber(streak) or 0), 0, #Daily.Coins)
	if lastClaimDay == day then return math.max(1, streak), true end
	if lastClaimDay == day - 1 then return streak % #Daily.Coins + 1, false end
	return 1, false
end

return Daily

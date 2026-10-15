return function(source)
	local hourly = assert(loadstring(source))()
	local function expect(actual, expected, label)
		assert(actual == expected, label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
	end

	local noon = hourly.ResetHourUtc * 3600
	expect(hourly.DayKey(noon - 1), -1, "minute before noon")
	expect(hourly.DayKey(noon), 0, "noon")
	expect(hourly.DayKey(noon + 86400), 1, "next noon")
	expect(hourly.DayKey(noon + 86399), 0, "second before the next noon")

	expect(#hourly.Due(5 * 60 - 1, 0), 0, "just before 5 minutes")
	local first = hourly.Due(5 * 60, 0)
	expect(#first, 1, "5 minute tier count")
	expect(first[1], 1, "5 minute tier")
	local afterFirst = hourly.Due(15 * 60, hourly.Mark(0, 1))
	expect(#afterFirst, 1, "only the unpaid tier")
	expect(afterFirst[1], 2, "15 minute tier")
	expect(#hourly.Due(60 * 60, 0), 5, "every tier at an hour")
	expect(#hourly.Due(60 * 60, hourly.Mark(hourly.Mark(hourly.Mark(hourly.Mark(hourly.Mark(0, 1), 2), 3), 4), 5)), 0, "paid hour")
	expect(hourly.Tiers[1].coins, 10, "5 minute coins")
	expect(hourly.Tiers[2].coins, 15, "15 minute coins")
	expect(hourly.Tiers[3].coins, 25, "30 minute coins")
	expect(hourly.Tiers[4].coins, 35, "45 minute coins")
	expect(hourly.Tiers[5].coins, 65, "60 minute coins")
	expect(hourly.Cap(), 3600, "cap")
	print("Hourly rewards: noon reset, tier times, and coin amounts passed")
end

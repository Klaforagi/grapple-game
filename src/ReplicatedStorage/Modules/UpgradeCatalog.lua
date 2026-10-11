-- Grapple gun ranks. Rank 0 is the live gun. Each stat has 10 purchased ranks.
-- Coin costs are the same for every stat. Change the table here to retune them.
-- RobuxPrice is one developer product per rank. RobuxProductId stays 0 until that product exists.
-- Speed: 40 + 11 per rank, so rank 10 is 150 studs/s.
-- Distance starts at 60 and ends at 300. Each purchase adds 4 more studs than the one before it.
-- Duration: 20 + 4 per rank, so rank 10 is 60 seconds.
-- Resistance: 5% per rank, so rank 10 cuts incoming tethers in half.
-- A tether never drops below MinTetherSeconds.

local Catalog = {}

Catalog.MaxRank = 10
Catalog.MinTetherSeconds = 2
-- Wall mode flies and reels at this multiple of the player's current hook distance.
Catalog.WallLengthScale = 3
Catalog.RobuxPrice = 299
Catalog.RobuxProductId = 0
-- Cost to leave this rank. Index 1 buys rank 1.
Catalog.Costs = {25, 60, 125, 250, 500, 1000, 2000, 3500, 6000, 10000}

Catalog.Stats = {
	{
		id = "speed",
		name = "Hook Speed",
		description = "Increase grapple projectile speed",
		attribute = "HookSpeedRank",
		base = 40,
		perRank = 11,
		accent = "speed",
	},
	{
		id = "distance",
		name = "Hook Distance",
		description = "Increase maximum hook distance",
		attribute = "HookDistanceRank",
		-- Rank 0 through 10. Gains are +6, +10, +14, +18, +22, +26, +30, +34, +38, +42.
		values = {60, 66, 76, 90, 108, 130, 156, 186, 220, 258, 300},
		accent = "distance",
	},
	{
		id = "duration",
		name = "Tether Duration",
		description = "Hold players for longer",
		attribute = "TetherDurationRank",
		base = 20,
		perRank = 4,
		accent = "duration",
	},
	{
		id = "resistance",
		name = "Tether Resistance",
		description = "Reduce how long others can hold you",
		attribute = "TetherResistanceRank",
		base = 0,
		perRank = 0.05,
		accent = "resistance",
	},
}

Catalog.ById = {}
for _, stat in ipairs(Catalog.Stats) do
	Catalog.ById[stat.id] = stat
end

function Catalog.Find(id)
	if type(id) ~= "string" then return nil end
	return Catalog.ById[id]
end

function Catalog.ClampRank(rank)
	if type(rank) ~= "number" or rank ~= rank then return 0 end
	return math.clamp(math.floor(rank), 0, Catalog.MaxRank)
end

function Catalog.Rank(player, id)
	local stat = Catalog.Find(id)
	if not stat or not player or type(player.GetAttribute) ~= "function" then return 0 end
	return Catalog.ClampRank(player:GetAttribute(stat.attribute))
end

function Catalog.Cost(rank)
	rank = Catalog.ClampRank(rank)
	return Catalog.Costs[rank + 1]
end

function Catalog.Value(stat, rank)
	rank = Catalog.ClampRank(rank)
	if stat.values then return stat.values[rank + 1] end
	if stat.id == "resistance" then
		return rank * 5 / 100
	end
	return stat.base + stat.perRank * rank
end

function Catalog.Text(stat, rank)
	rank = Catalog.ClampRank(rank)
	if stat.id == "resistance" then
		return tostring(rank * 5) .. "%"
	end
	if stat.id == "duration" then
		local tenths = math.floor(Catalog.Value(stat, rank) * 10 + 0.5)
		local whole = math.floor(tenths / 10)
		local fraction = tenths % 10
		if fraction == 0 then return tostring(whole) .. "s" end
		return string.format("%d.%ds", whole, fraction)
	end
	local value = Catalog.Value(stat, rank)
	if stat.id == "speed" then return tostring(value) .. " studs/s" end
	return tostring(value) .. " studs"
end

function Catalog.HookSpeed(player)
	return Catalog.Value(Catalog.ById.speed, Catalog.Rank(player, "speed"))
end

function Catalog.HookDistance(player)
	return Catalog.Value(Catalog.ById.distance, Catalog.Rank(player, "distance"))
end

function Catalog.ShotDistance(player, wallMode)
	local distance = Catalog.HookDistance(player)
	if wallMode then distance *= Catalog.WallLengthScale end
	return distance
end

function Catalog.TetherDuration(player)
	return Catalog.Value(Catalog.ById.duration, Catalog.Rank(player, "duration"))
end

function Catalog.Resistance(player)
	return Catalog.Value(Catalog.ById.resistance, Catalog.Rank(player, "resistance"))
end

function Catalog.ApplyResistance(duration, resistance)
	local held = duration * (1 - resistance)
	if held < Catalog.MinTetherSeconds then held = Catalog.MinTetherSeconds end
	return held
end

-- victim is nil for an NPC, which has no resistance.
function Catalog.HeldSeconds(grappler, victim)
	local duration = Catalog.TetherDuration(grappler)
	if victim then duration = Catalog.ApplyResistance(duration, Catalog.Resistance(victim)) end
	return duration
end

return Catalog

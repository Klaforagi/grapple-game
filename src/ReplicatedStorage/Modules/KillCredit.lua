-- Environment kills are credited to a player. The grapple record is the last
-- person who caught this humanoid. Lava and the void only count when that
-- grapple is still on, or was released inside its window. Freeze uses the
-- player who closed the capsule. The crusher uses the lever, unless the
-- victim is grappled right then.

local M = {}

M.LavaWindow = 20
M.VoidWindow = 5

M.Lines = {
	Lava = {
		"{Killer} gave {Victim} a lava bath.",
		"{Killer} cooked {Victim} alive.",
		"{Killer} turned {Victim} into ashes.",
		"{Killer} sent {Victim} into the lava.",
		"{Killer} melted {Victim}.",
		"{Killer} turned up the heat on {Victim}.",
		"{Killer} served {Victim} extra crispy.",
		"{Killer} made {Victim} into BBQ.",
		"{Killer} threw {Victim} into the furnace.",
		"{Killer} made sure {Victim} couldn't handle the heat.",
	},
	Void = {
		"{Killer} sent {Victim} flying.",
		"{Killer} threw {Victim} into the void.",
		"{Killer} introduced {Victim} to gravity.",
		"{Killer} sent {Victim} on a one-way trip.",
		"{Killer} launched {Victim} into oblivion.",
		"{Killer} helped {Victim} discover the edge of the world.",
		"{Killer} gave {Victim} flying lessons.",
		"{Killer} sent {Victim} sightseeing.",
		"{Killer} removed {Victim} from the map.",
		"{Killer} made {Victim} take the express route down.",
	},
	Freeze = {
		"{Killer} turned {Victim} into a popsicle.",
		"{Killer} put {Victim} on ice.",
		"{Killer} froze {Victim} solid.",
		"{Killer} gave {Victim} the cold shoulder.",
		"{Killer} sent {Victim} into cryosleep.",
		"{Killer} made {Victim} chill out.",
		"{Killer} left {Victim} out in the cold.",
		"{Killer} gave {Victim} a permanent brain freeze.",
		"{Killer} added {Victim} to the frozen collection.",
		"{Killer} put {Victim} in cold storage.",
	},
	Crusher = {
		"{Killer} turned {Victim} into a pancake.",
		"{Killer} flattened {Victim}.",
		"{Killer} crushed {Victim}.",
		"{Killer} put {Victim} under pressure.",
		"{Killer} squished {Victim}.",
		"{Killer} made {Victim} two-dimensional.",
		"{Killer} pressed {Victim} into oblivion.",
		"{Killer} compressed {Victim} into a smaller package.",
		"{Killer} gave {Victim} a crushing defeat.",
		"{Killer} made {Victim} fit into tight spaces.",
	},
}

-- A death with nobody else involved. Shown in the feed, not added to a total.
M.SoloLines = {
	Lava = "{Player} took a lava bath",
	Void = "{Player} is still falling",
	Crusher = "{Player} became a pancake",
}

local records = setmetatable({}, {__mode = "k"})
local reported = setmetatable({}, {__mode = "k"})
local listener = nil
local queued = nil

local function clipName(text)
	if type(text) ~= "string" then return "Player" end
	text = text:gsub("[%c]", "")
	if text == "" then return "Player" end
	if #text > 40 then text = string.sub(text, 1, 40) end
	return text
end

local function escapeName(text)
	return (clipName(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.Plain(line, killer, victim)
	if type(line) ~= "string" then return "" end
	local text = string.gsub(line, "{Killer}", function() return clipName(killer) end)
	return (string.gsub(text, "{Victim}", function() return clipName(victim) end))
end

function M.Format(line, killer, victim)
	if type(line) ~= "string" then return "" end
	local killerText = '<font color="#FFD68C"><b>' .. escapeName(killer) .. "</b></font>"
	local victimText = '<font color="#FFFFFF"><b>' .. escapeName(victim) .. "</b></font>"
	local text = string.gsub(line, "{Killer}", function() return killerText end)
	return (string.gsub(text, "{Victim}", function() return victimText end))
end

function M.NoteAttach(humanoid, grapplerId, grapplerName)
	if not humanoid or type(grapplerId) ~= "number" then return end
	records[humanoid] = {
		id = grapplerId,
		name = type(grapplerName) == "string" and clipName(grapplerName) or nil,
		active = true,
	}
end

-- A stale disconnect must not clear a newer grappler's record.
function M.NoteRelease(humanoid, grapplerId, now)
	local record = humanoid and records[humanoid]
	if not record or not record.active then return end
	if type(grapplerId) == "number" and record.id ~= grapplerId then return end
	if type(now) ~= "number" then return end
	record.active = false
	record.releasedAt = now
end

function M.IsActive(humanoid, grapplerId)
	local record = humanoid and records[humanoid]
	if not record or not record.active then return false end
	if grapplerId ~= nil and record.id ~= grapplerId then return false end
	return true
end

local function recentGrappler(record, now, window)
	if not record or type(record.id) ~= "number" then return nil end
	if record.active then return record.id end
	-- (t + window) - t can land a few ulps over the window. A microsecond still
	-- counts as the boundary.
	if type(record.releasedAt) == "number" and now - record.releasedAt <= window + 1e-6 then
		return record.id
	end
	return nil
end

local function attributeNumber(humanoid, name)
	local value = humanoid:GetAttribute(name)
	if type(value) == "number" then return value end
	return nil
end

local function solo(cause, victimId)
	return {
		cause = cause,
		killerId = victimId,
		count = false,
		show = true,
		solo = true,
	}
end

local function credit(cause, killerId, victimId, killerName, count)
	if type(killerId) ~= "number" then return nil end
	-- A crusher can list the victim as their own killer. That line is shown and
	-- is not added to the kill total. Every other cause needs a different player.
	if killerId == victimId and cause ~= "Crusher" then return nil end
	local selfKill = killerId == victimId
	return {
		cause = cause,
		killerId = killerId,
		killerName = killerName,
		count = count and not selfKill,
		show = true,
	}
end

function M.Resolve(victimId, humanoid, now)
	if type(victimId) ~= "number" or type(now) ~= "number" or not humanoid or not humanoid.GetAttribute then
		return nil
	end
	local cause = humanoid:GetAttribute("DeathCause")
	if type(cause) ~= "string" then return nil end
	local record = records[humanoid]
	local killerName = record and record.name or nil

	if cause == "Lava" then
		local killerId = recentGrappler(record, now, M.LavaWindow)
		if killerId and killerId ~= victimId then
			return credit("Lava", killerId, victimId, record.id == killerId and killerName or nil, true)
		end
		return solo("Lava", victimId)
	end
	if cause == "Void" then
		local killerId = recentGrappler(record, now, M.VoidWindow)
		if killerId and killerId ~= victimId then
			return credit("Void", killerId, victimId, record.id == killerId and killerName or nil, true)
		end
		return solo("Void", victimId)
	end
	if cause == "Freeze" then
		local killerId = attributeNumber(humanoid, "DeathFreezer")
		if not killerId or killerId == victimId then return nil end
		local name = record and record.id == killerId and killerName or nil
		return credit("Freeze", killerId, victimId, name, true)
	end
	if cause == "Crusher" then
		-- Current tether wins over the lever. A released grapple does not.
		local killerId = attributeNumber(humanoid, "DeathGrappler") or attributeNumber(humanoid, "DeathPuller")
		if not killerId then return nil end
		if killerId == victimId then return solo("Crusher", victimId) end
		local name = record and record.id == killerId and killerName or nil
		return credit("Crusher", killerId, victimId, name, true)
	end
	return nil
end

function M.SetListener(fn)
	listener = fn
	local waiting = queued
	queued = nil
	if type(fn) ~= "function" or not waiting then return end
	for _, item in ipairs(waiting) do
		local ok, err = pcall(fn, item.result, item.player)
		if not ok then warn("[Kills] " .. tostring(err)) end
	end
end

function M.Report(player, humanoid, now)
	if not humanoid or reported[humanoid] then return nil end
	reported[humanoid] = true
	local victimId = player and player.UserId
	local result = type(victimId) == "number" and M.Resolve(victimId, humanoid, now) or nil
	records[humanoid] = nil
	pcall(function()
		humanoid:SetAttribute("DeathCause", nil)
		humanoid:SetAttribute("DeathFreezer", nil)
		humanoid:SetAttribute("DeathPuller", nil)
		humanoid:SetAttribute("DeathGrappler", nil)
	end)
	if not result then return nil end
	result.victimId = victimId
	if type(listener) == "function" then
		local ok, err = pcall(listener, result, player)
		if not ok then warn("[Kills] " .. tostring(err)) end
	else
		queued = queued or {}
		queued[#queued + 1] = {result = result, player = player}
	end
	return result
end

return M

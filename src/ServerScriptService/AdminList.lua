-- Server only. Add a user id here to grant the Admin menu.
-- Clients never receive this module. The server still checks this list on every action.
local ids = {
	1127843745,
}

local lookup = {}
for _, id in ipairs(ids) do
	if type(id) == "number" then lookup[id] = true end
end

local AdminList = {}

function AdminList.IsAdmin(userId)
	return type(userId) == "number" and lookup[userId] == true
end

return AdminList

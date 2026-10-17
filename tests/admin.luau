return function(sources)
	local listFn = assert(loadstring(sources.adminList))
	setfenv(listFn, setmetatable({}, {__index = getfenv()}))
	local list = listFn()
	assert(list.IsAdmin(1127843745), "owner is not an admin")
	assert(not list.IsAdmin(5), "stranger is an admin")
	assert(not list.IsAdmin("1127843745"), "admin id was accepted as text")

	local now, guid = 0, 0
	local replies, calls = {}, {}
	local seeded = {
		GrappleBans_v1 = {
			player_99 = {banned = true, reason = "cheating"},
			player_1127843745 = {banned = true, reason = "ignore"},
		},
		GrappleCoins_v1 = {
			player_77 = {coins = 5, earned = 8, name = "OfflineDisplay", username = "OfflineUser"},
		},
		GrappleRobuxSpent_v1 = {player_77 = {spent = 123}},
		GrappleKills_v1 = {player_77 = {kills = 2}},
		GrapplePlayedTime_v1 = {player_77 = {seconds = 90}},
		GrappleUpgrades_v1 = {
			player_77 = {speed = 3, distance = 4, duration = 5, resistance = 6, purchases = {keep = true}},
		},
		GrappleCosmetics_v1 = {player_77 = {GrappleGunColor = "Red"}},
	}
	local databases = {}
	local function database(name)
		local found = databases[name]
		if found then return found end
		local rows = seeded[name] or {}
		seeded[name] = rows
		local db = {
			GetAsync = function(_, key) return rows[key] end,
			UpdateAsync = function(_, key, transform)
				rows[key] = transform(rows[key])
				return rows[key]
			end,
		}
		databases[name] = db
		return db
	end

	local function new(className)
		local obj = {ClassName = className, children = {}}
		function obj:FindFirstChild(name) return self.children[name] end
		function obj:WaitForChild(name)
			local found = self.children[name]
			if not found then error("missing " .. tostring(name)) end
			return found
		end
		function obj:IsA(kind) return self.ClassName == kind end
		function obj:FireClient(player, payload)
			replies[#replies + 1] = {player = player, payload = payload}
		end
		return setmetatable(obj, {
			__newindex = function(self, key, value)
				rawset(self, key, value)
				if key == "Parent" and type(value) == "table" and type(value.children) == "table" and type(self.Name) == "string" then
					value.children[self.Name] = self
				end
			end,
			__index = function(self, key)
				if key == "OnServerEvent" or key == "OnClientEvent" then
					local signal = rawget(self, key)
					if not signal then
						signal = {}
						function signal:Connect(fn) rawset(obj, "_handler", fn) end
						rawset(self, key, signal)
					end
					return signal
				end
				return nil
			end,
		})
	end

	local replicated = new("ReplicatedStorage")
	local colors = new("ModuleScript")
	colors.Name = "ItemColors"
	colors.Parent = replicated

	local function binder(name, fn)
		local obj = {Name = name}
		function obj:Invoke(...)
			local args = table.pack(...)
			calls[#calls + 1] = {name = name, args = args}
			return fn(table.unpack(args, 1, args.n))
		end
		replicated.children[name] = obj
	end
	binder("GrantCoins", function() return true end)
	binder("SpendCoins", function() error("spend") end)
	binder("AdminCoins", function(action, userId)
		if action == "read" and userId == 42 then return {coins = 3, earned = 9} end
		if action == "reset" or action == "grant" then return true end
		return nil
	end)
	binder("AdminKills", function(action, userId)
		if action == "read" and userId == 42 then return {kills = 4} end
		if action == "reset" then return true end
		return nil
	end)
	binder("AdminPlayedTime", function(action, userId)
		if action == "read" and userId == 42 then return {seconds = 120} end
		if action == "reset" then return true end
		return nil
	end)
	binder("AdminUpgrades", function(action, userId)
		if action == "read" and userId == 42 then
			return {speed = 2, distance = 1, duration = 0, resistance = 4}
		end
		if action == "reset" then return true end
		return nil
	end)
	binder("AdminSetGrappleColor", function() return true end)

	local function makePlayer(name, id)
		local attributes = {}
		local player = {Name = name, DisplayName = name .. "Display", UserId = id}
		function player:SetAttribute(key, value) attributes[key] = value end
		function player:GetAttribute(key) return attributes[key] end
		function player:Kick(message) self.kicked = message end
		return player
	end
	local owner = makePlayer("Owner", 1127843745)
	local stranger = makePlayer("Stranger", 5)
	local banned = makePlayer("Banned", 99)
	local listPlayers = {owner, stranger, banned}
	local players = {
		PlayerAdded = {Connect = function() end},
	}
	function players:GetPlayers() return listPlayers end
	function players:GetPlayerByUserId(id)
		for _, player in ipairs(listPlayers) do
			if player.UserId == id then return player end
		end
	end
	function players:GetNameFromUserIdAsync(id)
		if id == 1127843745 then return "Owner" end
		if id == 42 then return "Target" end
		if id == 77 then return "OfflineUser" end
		error("no user")
	end
	function players:GetUserIdFromNameAsync(name)
		if name == "Target" then return 42 end
		if name == "OfflineUser" then return 77 end
		error("no user")
	end
	for _, player in ipairs(listPlayers) do player.Parent = players end

	local env = setmetatable({
		game = {
			GetService = function(_, name)
				if name == "Players" then return players end
				if name == "DataStoreService" then
					return {GetDataStore = function(_, storeName) return database(storeName) end}
				end
				if name == "ReplicatedStorage" then return replicated end
				if name == "HttpService" then
					return {GenerateGUID = function() guid += 1 return "guid-" .. guid end}
				end
				error(name)
			end,
		},
		Instance = {new = new},
		os = {clock = function() return now end, time = function() return 5000 end},
		task = {spawn = function(fn, ...) fn(...) end, wait = function() now += 0.1 end},
		warn = function() end,
		script = {
			Name = "Admin",
			Parent = {WaitForChild = function(_, name)
				assert(name == "AdminList", name)
				return {Name = "AdminList"}
			end},
		},
	}, {__index = getfenv()})
	env.require = function(module)
		if module.Name == "AdminList" then
			local fn = assert(loadstring(sources.adminList))
			setfenv(fn, env)
			return fn()
		end
		if module.Name == "ItemColors" then
			return {
				Gun = {Red = {}, Gold = {}},
				Rope = {Blue = {}, Red = {}},
				Bomb = {Red = {}, Mint = {}, Green = {}},
			}
		end
		error("require " .. tostring(module.Name))
	end

	local fn = assert(loadstring(sources.admin))
	setfenv(fn, env)
	fn()

	assert(owner:GetAttribute("Admin") == true, "owner attribute was not set")
	assert(owner.kicked == nil, "admin ban record kicked the owner")
	assert(stranger:GetAttribute("Admin") == nil, "stranger received admin")
	assert(stranger.kicked == nil, "stranger was kicked")
	assert(banned:GetAttribute("Admin") == nil, "banned player received admin")
	assert(type(banned.kicked) == "string" and string.find(banned.kicked, "cheating", 1, true), "ban did not kick on join")
	assert(seeded.GrappleBans_v1.player_1127843745.reason == "ignore", "join rewrote the owner ban row")

	local request = replicated:FindFirstChild("Remotes"):FindFirstChild("AdminRequest")
	local function count(name, action)
		local total = 0
		for _, call in ipairs(calls) do
			if call.name == name and (action == nil or call.args[1] == action) then total += 1 end
		end
		return total
	end
	local function fire(player, payload)
		now += 1
		request._handler(player, payload)
	end
	local function last()
		return replies[#replies].payload
	end

	fire(stranger, {action = "grant", user = "42", amount = "25"})
	assert(count("GrantCoins") == 0 and count("AdminCoins", "grant") == 0, "stranger gave coins")
	assert(last().ok == false and last().message == "Not allowed.", "stranger was not refused")

	fire(owner, {action = "grant", user = "42", amount = "25"})
	assert(count("GrantCoins") == 0, "admin grant changed lifetime coins")
	assert(count("AdminCoins", "grant") == 1, "admin grant did not give held coins")
	local grant = calls[#calls]
	assert(grant.args[1] == "grant" and grant.args[2] == 42 and grant.args[3] == 25, "grant args were wrong")
	assert(grant.args[3] > 0, "grant amount was not positive")
	assert(last().ok == true, "grant did not succeed")

	local before = count("AdminCoins", "grant")
	fire(owner, {action = "grant", user = "42", amount = "0"})
	fire(owner, {action = "grant", user = "42", amount = "-5"})
	fire(owner, {action = "grant", user = "42", amount = "100000001"})
	assert(count("AdminCoins", "grant") == before, "rejected grant still paid")

	now = 50
	request._handler(owner, {action = "grant", user = "42", amount = "5"})
	local paced = count("AdminCoins", "grant")
	request._handler(owner, {action = "grant", user = "42", amount = "5"})
	assert(count("AdminCoins", "grant") == paced, "rapid grant was not limited")
	assert(last().message == "Slow down.", "rapid grant message was wrong")

	local target = makePlayer("Target", 42)
	target.Parent = players
	target:SetAttribute("SettingsLoaded", true)
	listPlayers[#listPlayers + 1] = target

	fire(owner, {action = "lookup", user = "Target"})
	assert(last().ok == true and last().profile.userId == 42, "username lookup missed the user")
	assert(last().profile.coins == 3 and last().profile.coinsEarned == 9, "live coins were not used")
	assert(last().profile.robuxSpent == 0, "new players should start with no tracked spending")
	assert(last().profile.kills == 4 and last().profile.playedSeconds == 120, "live stats were not used")
	assert(last().profile.speed == 2 and last().profile.resistance == 4, "live ranks were not used")
	assert(last().profile.online == true, "online player looked offline")

	fire(owner, {action = "lookup", user = "77"})
	local offline = last().profile
	assert(offline.coins == 5 and offline.coinsEarned == 8, "offline coins were wrong")
	assert(offline.robuxSpent == 123, "offline Robux spending was not loaded")
	assert(offline.kills == 2 and offline.playedSeconds == 90, "offline stats were wrong")
	assert(offline.speed == 3 and offline.distance == 4 and offline.duration == 5 and offline.resistance == 6, "offline ranks were wrong")
	assert(offline.gun == "Red" and offline.displayName == "OfflineDisplay", "offline profile missed saved fields")
	assert(offline.online == false and offline.banned == false, "offline flags were wrong")
	assert(offline.username == "OfflineUser", "offline username was wrong")

	fire(owner, {action = "lookup", user = "Nope"})
	assert(last().ok == false, "unknown username succeeded")

	fire(owner, {action = "ban", user = "Target", reason = "camping\nthe roof"})
	assert(target.kicked ~= nil and string.find(target.kicked, "camping the roof", 1, true), "ban did not kick")
	assert(seeded.GrappleBans_v1.player_42.banned == true, "ban was not saved")
	assert(seeded.GrappleBans_v1.player_42.by == 1127843745, "ban did not record the admin")

	fire(owner, {action = "ban", user = "1127843745", reason = "nope"})
	assert(last().ok == false, "admin ban was accepted")
	assert(owner.kicked == nil, "admin ban kicked the owner")
	assert(seeded.GrappleBans_v1.player_1127843745.reason == "ignore", "admin ban rewrote the row")

	fire(owner, {action = "unban", user = "42"})
	assert(seeded.GrappleBans_v1.player_42.banned == false, "unban did not clear the ban")

	fire(owner, {action = "reset", user = "Target", kind = "coins"})
	assert(count("SpendCoins") == 0, "coin reset spent coins")
	local coinReset
	for index = #calls, 1, -1 do
		if calls[index].name == "AdminCoins" and calls[index].args[1] == "reset" then coinReset = calls[index] break end
	end
	assert(coinReset and coinReset.args[2] == 42, "coin reset missed the user")
	fire(owner, {action = "reset", user = "42", kind = "all"})
	local kinds = {}
	for _, call in ipairs(calls) do
		if call.args[1] == "reset" then kinds[#kinds + 1] = call.name end
	end
	assert(kinds[1] == "AdminCoins" and kinds[2] == "AdminCoins", "coin reset did not run before reset all")
	assert(kinds[3] == "AdminKills" and kinds[4] == "AdminPlayedTime" and kinds[5] == "AdminUpgrades", "reset all order was wrong")
	assert(#kinds == 5, "reset all called the wrong number of resets")

	local colorsBefore = count("AdminSetGrappleColor")
	fire(owner, {action = "color", user = "42", target = "Bomb", color = "Teal"})
	assert(count("AdminSetGrappleColor") == colorsBefore + 1, "online color was not applied")
	local colorCall = calls[#calls]
	assert(colorCall.args[1] == 42 and colorCall.args[2] == "Bomb" and colorCall.args[3] == "Mint", "bomb teal was not saved as mint")
	assert(seeded.GrappleCosmetics_v1.player_42 == nil, "online color wrote the offline store")

	fire(owner, {action = "color", user = "42", target = "Gun", color = "Purple"})
	assert(count("AdminSetGrappleColor") == colorsBefore + 1, "unknown color was applied")
	assert(last().ok == false, "unknown color succeeded")

	fire(owner, {action = "color", user = "77", target = "Gun", color = "Gold"})
	assert(count("AdminSetGrappleColor") == colorsBefore + 1, "offline color used the live painter")
	assert(seeded.GrappleCosmetics_v1.player_77.GrappleGunColor == "Gold", "offline color was not saved")
	assert(last().ok == true, "offline color failed")

	fire(stranger, {action = "players"})
	assert(last().ok == false and last().players == nil, "stranger listed the server")
	fire(owner, {action = "players"})
	local seen = {}
	for _, row in ipairs(last().players) do seen[row.userId] = row end
	assert(seen[1127843745] and seen[42] and seen[5], "server list missed a player")
	assert(seen[42].username == "Target", "server list username was wrong")

	local function cf(x, y, z)
		return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, {
			__mul = function(a, b) return cf(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		})
	end
	env.CFrame = {new = function(x, y, z) return cf(x, y, z) end}
	local function attach(player, x, y, z)
		local humanoid = {Health = 100, WalkSpeed = 16, JumpPower = 50, UseJumpPower = false}
		local root = {ClassName = "BasePart", CFrame = cf(x, y, z)}
		function root:IsA(kind) return kind == "BasePart" end
		local character = {}
		function character:FindFirstChild(name)
			if name == "HumanoidRootPart" then return root end
		end
		function character:FindFirstChildOfClass(class)
			if class == "Humanoid" then return humanoid end
		end
		player.Character = character
		return humanoid, root
	end
	local humanoid, targetRoot = attach(target, 10, 0, 0)
	local _, ownerRoot = attach(owner, 0, 0, 0)
	fire(owner, {action = "bring", userId = 42})
	assert(targetRoot.CFrame.X == 0 and targetRoot.CFrame.Y == 3 and targetRoot.CFrame.Z == -4, "teleport did not bring them")
	targetRoot.CFrame = cf(10, 0, 0)
	fire(owner, {action = "goto", userId = 42})
	assert(ownerRoot.CFrame.X == 10 and ownerRoot.CFrame.Y == 3 and ownerRoot.CFrame.Z == -4, "teleport to did not move you")
	fire(owner, {action = "boost", userId = 42, kind = "speed"})
	assert(humanoid.WalkSpeed == 24, "speed was not 24")
	fire(owner, {action = "boost", userId = 42, kind = "jump"})
	assert(humanoid.UseJumpPower == true and humanoid.JumpPower == 80, "jump power was not 80")
	fire(stranger, {action = "boost", userId = 42, kind = "speed"})
	assert(humanoid.WalkSpeed == 24, "stranger changed speed")

	local noclip = replicated:FindFirstChild("Remotes"):FindFirstChild("AdminNoclip")
	noclip._handler(stranger)
	assert(stranger:GetAttribute("Noclip") == nil, "stranger turned noclip on")
	noclip._handler(owner)
	assert(owner:GetAttribute("Noclip") == true, "admin noclip did not turn on")
	noclip._handler(owner)
	assert(owner:GetAttribute("Noclip") == false, "admin noclip did not turn off")

	local motionChunk = assert(loadstring(sources.noclip))
	setfenv(motionChunk, setmetatable({}, {__index = getfenv()}))
	local motion = motionChunk()
	local lookForward, lookRight = {X = 0, Y = 0, Z = -1}, {X = 1, Y = 0, Z = 0}
	local fx, fy, fz = motion.Direction({w = true}, lookForward, lookRight)
	assert(math.abs(fx) < 1e-6 and math.abs(fy) < 1e-6 and math.abs(fz + 1) < 1e-6, "forward fly left the look direction")
	local ux, uy, uz = motion.Direction({w = true}, {X = 0, Y = 1, Z = 0}, lookRight)
	assert(math.abs(ux) < 1e-6 and math.abs(uy - 1) < 1e-6 and math.abs(uz) < 1e-6, "looking up did not fly up")
	local dx, dy, dz = motion.Direction({w = true, up = true}, lookForward, lookRight)
	assert(math.abs(dx) < 1e-6 and math.abs(dy - 0.70710678) < 1e-4 and math.abs(dz + 0.70710678) < 1e-4, "space did not add lift")
	local zx, zy, zz = motion.Direction({}, lookForward, lookRight)
	assert(zx == 0 and zy == 0 and zz == 0, "idle fly drifted")
	local yawX, yawZ = motion.FlatLook({X = 3, Y = 5, Z = 4})
	assert(math.abs(yawX - 0.6) < 1e-6 and math.abs(yawZ - 0.8) < 1e-6, "body yaw did not follow the mouse")
	local upX = motion.FlatLook({X = 0, Y = -1, Z = 0})
	assert(upX == nil, "straight up produced a yaw")
	assert(motion.SpeedFor(false) == 80 and motion.SpeedFor(true) == 200, "noclip speeds drifted")
	local moved = motion.Move({X = 0, Y = 10, Z = 0}, {X = 0, Y = 0, Z = -1}, 80, 5)
	assert(moved.Y == 10 and math.abs(moved.Z + 8) < 1e-6, "a hitch stepped farther than one tenth of a second")
	local vectorLook, vectorRight = vector.create(0, 0, -1), vector.create(1, 0, 0)
	local vx, vy, vvz = motion.Direction({w = true}, vectorLook, vectorRight)
	assert(math.abs(vx) < 1e-6 and math.abs(vy) < 1e-6 and math.abs(vvz + 1) < 1e-6, "vector look was ignored")
	local movedVector = motion.Move(vector.create(10, 20, 30), vector.create(1, 0, 0), 80, 0.1)
	assert(math.abs(movedVector.X - 18) < 1e-6 and movedVector.Y == 20 and movedVector.Z == 30, "vector position was treated as the origin")
	print("PASS: admin list, grants, lookup, bans, resets, colors, server actions, and noclip")
end

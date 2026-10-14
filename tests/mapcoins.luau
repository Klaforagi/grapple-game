return function(source)
	local now = 0
	local grants = {}
	local guid = 0
	local blocked = true
	local cover = false
	local heartbeats = {}
	local remoteFn
	local fired = {}
	local foldersMade = 0
	local function vec(x, y, z)
		return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, {
			__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
			__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
			__index = function(a, key)
				if key == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
			end,
		})
	end
	local cfMT = {__add = function(a, b) return setmetatable({Position = a.Position + b}, cfMT) end}
	local function cframe(position)
		return setmetatable({Position = position or vec()}, cfMT)
	end
	local grass = {Name = "Grass", Size = vec(80, 2, 80), Material = "Grass",
		CFrame = {PointToWorldSpace = function(_, point) return point end}}
	function grass:IsA(class) return class == "BasePart" end
	function grass:IsDescendantOf() return false end
	local leaves = {Name = "Leaves", Material = "Grass", Size = vec(8, 6, 8), Parent = true}
	function leaves:IsA(class) return class == "BasePart" end
	function leaves:IsDescendantOf() return false end
	leaves.CFrame = {PointToObjectSpace = function() return cover and vec() or vec(500, 0, 0) end}
	local tree = {Name = "Trunk"}
	function tree:IsA(class) return class == "BasePart" end
	local folder = {Name = "MapCoins", children = {}}
	function folder:IsA(class) return class == "Folder" end
	function folder:IsDescendantOf() return false end
	local function track(model)
		local current
		local object = {}
		return setmetatable(object, {
			__index = function(_, key)
				if key == "Parent" then return current end
				return model[key]
			end,
			__newindex = function(_, key, value)
				if key == "Parent" then
					if current and current.children then current.children[object] = nil end
					if value and value.children then value.children[object] = true end
					current = value
					return
				end
				rawset(object, key, value)
			end,
		})
	end
	local function coinModel()
		local touched = {}
		local part = {
			Name = "CoinPart", Size = vec(2, 2, 2), Anchored = false, CanCollide = true, CanTouch = false,
			Touched = {Connect = function(_, fn) touched.fn = fn return {Disconnect = function() end} end},
			IsA = function(_, class) return class == "BasePart" end,
		}
		local model = track({
			Name = "Coin", pivot = cframe(vec()),
			IsA = function(_, class) return class == "Model" end,
			GetDescendants = function() return {part} end,
			FindFirstChildWhichIsA = function() return part end,
			GetBoundingBox = function(self) return self.pivot, vec(2, 2, 2) end,
			GetPivot = function(self) return self.pivot end,
			PivotTo = function(self, nextPivot) self.pivot = nextPivot end,
			Destroy = function(self) self.Parent = nil end,
			IsDescendantOf = function(self, ancestor)
				local parent = self.Parent
				while parent do
					if parent == ancestor then return true end
					parent = parent.Parent
				end
				return false
			end,
		})
		function model:Clone()
			return coinModel()
		end
		return model
	end
	local template = coinModel()
	local storage = {Name = "ServerStorage"}
	function storage:FindFirstChild(name)
		return name == "Coin" and template or nil
	end
	template.Parent = storage
	local function onInvoke(userId, amount, id)
		grants[#grants + 1] = {userId = userId, amount = amount, id = id}
		return true
	end
	local grant = {
		Name = "GrantCoins",
		Invoke = function(_, ...) return onInvoke(...) end,
		OnInvoke = onInvoke,
	}
	local replicated = {Name = "ReplicatedStorage"}
	function replicated:FindFirstChild(name)
		if name == "GrantCoins" then return grant end
		if name == "GrappleConfig" then return {} end
		return nil
	end
	function replicated:WaitForChild(name) return self:FindFirstChild(name) end
	local workspace = {
		GetDescendants = function() return {grass, leaves} end,
		FindFirstChild = function() return nil end,
		Raycast = function() return {Position = vec(10, 1, 8), Normal = vec(0, 1, 0), Instance = grass} end,
		GetPartBoundsInBox = function() return blocked and {tree} or {} end,
	}
	local root = {Position = vec(0, 80, 0)}
	local humanoid = {Health = 100}
	local character = {
		FindFirstChild = function(_, name) return name == "HumanoidRootPart" and root or nil end,
		FindFirstChildOfClass = function(_, class) return class == "Humanoid" and humanoid or nil end,
	}
	local players = {}
	local player = {Name = "Picker", UserId = 15, Character = character, Parent = players}
	function players:GetPlayers() return {player} end
	function players:GetPlayerFromCharacter(model) return model == character and player or nil end
	local services = {
		HttpService = {GenerateGUID = function() guid += 1 return "id-" .. guid end},
		Players = players,
		ReplicatedStorage = replicated,
		ServerStorage = storage,
		Workspace = workspace,
		RunService = {Heartbeat = {Connect = function(_, fn) heartbeats[#heartbeats + 1] = fn end}},
	}
	local env = setmetatable({
		game = {GetService = function(_, name) return assert(services[name], name) end},
		workspace = workspace,
		Instance = {new = function(class)
			if class == "RemoteEvent" then
				local event = {Name = "CollectMapCoin"}
				event.OnServerEvent = {Connect = function(_, fn) remoteFn = fn end}
				function event:FireClient(...) fired[#fired + 1] = {...} end
				function event:IsA(kind) return kind == "RemoteEvent" end
				return event
			end
			assert(class == "Folder", class)
			foldersMade += 1
			if foldersMade == 1 then return folder end
			local extra = {Name = "", children = {}}
			function extra:IsA(kind) return kind == "Folder" end
			function extra:FindFirstChild(name)
				for child in pairs(self.children) do
					if child.Name == name then return child end
				end
				return nil
			end
			return extra
		end},
		Enum = {Material = {Grass = "Grass"}, RaycastFilterType = {Include = "Include", Exclude = "Exclude"}},
		RaycastParams = {new = function() return {} end},
		OverlapParams = {new = function() return {} end},
		Vector3 = {new = vec},
		CFrame = {new = function(position) return cframe(position) end},
		os = {clock = function() return now end},
		warn = function() end,
		require = function() return {mapCoinCap = 100, mapCoinRespawn = 300} end,
	}, {__index = getfenv()})
	local fn = assert(loadstring(source))
	setfenv(fn, env)
	fn()
	local function beat()
		for _, callback in ipairs(heartbeats) do callback() end
	end
	local function coins()
		local count = 0
		for _ in pairs(folder.children) do count += 1 end
		return count
	end
	beat()
	assert(coins() == 0, "coin spawned inside a nearby part")
	blocked = false
	now = 5
	beat()
	assert(coins() == 1, "open grass did not spawn a coin")
	assert(#grants == 0, "walking far away collected a coin")
	root.Position = vec(10, 3, 8)
	now = 10
	beat()
	local where = ""
	for item in pairs(folder.children) do
		local pivot = item.GetPivot and item:GetPivot()
		where ..= tostring(pivot and pivot.Position and pivot.Position.X) .. ","
			.. tostring(pivot and pivot.Position and pivot.Position.Y) .. ","
			.. tostring(pivot and pivot.Position and pivot.Position.Z) .. " "
	end
	assert(#grants == 1 and grants[1].userId == 15 and grants[1].amount == 1 and grants[1].id == "coin_id-1",
		"running over a coin did not pay 1 grants=" .. #grants .. " coins=" .. coins() .. " at " .. where)
	assert(coins() == 0, "collected coin stayed in the world")
	root.Position = vec(0, 80, 0)
	now += 299
	beat()
	assert(coins() == 0 and #grants == 1, "collected coin came back before 5 minutes")
	now += 1
	beat()
	assert(coins() == 1, "coin did not respawn after 5 minutes")
	beat()
	assert(coins() == 1 and #grants == 1, "respawned coin was collected without a player on it")
	local model
	for item in pairs(folder.children) do model = item end
	root.Position = vec(200, 3, 200)
	remoteFn(player, model)
	assert(coins() == 1 and #grants == 1, "a far collect request paid out")
	assert(fired[#fired][3] == false, "a far collect request was not refused")
	root.Position = vec(10, 3, 28)
	remoteFn(player, model)
	assert(#grants == 2 and grants[2].amount == 1 and coins() == 0, "a lagged runner could not collect")
	assert(fired[#fired][1] == player and fired[#fired][3] == 1, "collect did not report the paid amount")
	cover = true
	now += 300
	beat()
	assert(coins() == 0, "coin spawned inside a Leaves part")
	cover = false
	now += 5
	beat()
	assert(coins() == 1, "open grass stayed empty after the leaves moved")
end

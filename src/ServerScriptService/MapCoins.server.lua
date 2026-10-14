-- Grass pickups. A Coin model in ServerStorage (or ReplicatedStorage, or the map)
-- is copied onto open Grass parts. Up to mapCoinCap stay until collected.
-- Each pickup pays 1 coin, then another appears mapCoinRespawn seconds later.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local MAX_COINS = Config.mapCoinCap or 100
local RESPAWN_SECONDS = Config.mapCoinRespawn or 300
local ZONE_CAP = Config.mapCoinZoneCap or 4
local REACH = Config.mapCoinReach or 48
local REACH_Y = 24
local CLEAR_PADDING = 6
local COIN_SEPARATION = 12
local ATTEMPTS = 25
local SPAWNS_PER_STEP = 4
local RETRY_SECONDS = 5
local GRASS_REFRESH = 10

local coinsFolder = Instance.new("Folder")
coinsFolder.Name = "MapCoins"
coinsFolder.Parent = Workspace

local template
local warnedTemplate, warnedGrass = false, false
local grass, grassAt = {}, 0
local alive = {}
local foliage = {}
local unspawned = MAX_COINS
local delayed = {}
local retryAt = 0
local collectRemote
local doubleId
local ownsDouble = {}

local function isFoliage(part)
	local name = string.lower(tostring(part.Name or ""))
	return string.find(name, "leaf", 1, true) ~= nil or string.find(name, "leave", 1, true) ~= nil
end

local function isGrass(part)
	-- Tree canopies often use the Grass material on a part named Leaves.
	return part:IsA("BasePart") and not isFoliage(part)
		and (part.Name == "Grass" or part.Material == Enum.Material.Grass)
end

local function characterOf(part)
	if not part or not part.FindFirstAncestorOfClass then return nil end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return model end
	return nil
end

local function findTemplate()
	for _, container in ipairs({ServerStorage, ReplicatedStorage}) do
		local found = container:FindFirstChild("Coin")
		if found and (found:IsA("Model") or found:IsA("BasePart")) then return found end
	end
	local found = Workspace:FindFirstChild("Coin", true)
	if not found or not (found:IsA("Model") or found:IsA("BasePart")) then return nil end
	if found:IsDescendantOf(coinsFolder) then return nil end
	-- The map copy is the art source. Keep it out of the pickup folder.
	found.Parent = ServerStorage
	return found
end

local function measure(object)
	if object.GetBoundingBox then
		local cf, size = object:GetBoundingBox()
		if cf and size then return cf, size end
	end
	local part = object:IsA("BasePart") and object or object:FindFirstChildWhichIsA("BasePart", true)
	local size = part and part.Size or Vector3.new(2, 2, 2)
	local cf = object.GetPivot and object:GetPivot() or CFrame.new()
	return cf, size
end

local function refreshGrass(now)
	if now - grassAt < GRASS_REFRESH and #grass > 0 then return end
	grassAt = now
	table.clear(grass)
	table.clear(foliage)
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("BasePart") and not item:IsDescendantOf(coinsFolder) and not characterOf(item) then
			if isFoliage(item) then foliage[#foliage + 1] = item end
			if isGrass(item) and item.Size.X >= 4 and item.Size.Z >= 4 then
				grass[#grass + 1] = item
			end
		end
	end
	if #grass == 0 and not warnedGrass then
		warnedGrass = true
		warn("[MapCoins] No Grass parts at least 4 studs across")
	end
end

local function pickGrass()
	local total = 0
	for _, part in ipairs(grass) do total += part.Size.X * part.Size.Z end
	if total <= 0 then return nil end
	local roll = math.random() * total
	local walked = 0
	for _, part in ipairs(grass) do
		walked += part.Size.X * part.Size.Z
		if walked >= roll then return part end
	end
	return grass[#grass]
end

local function tooClose(position)
	for _, coin in ipairs(alive) do
		local offset = coin.position - position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < COIN_SEPARATION then return true end
	end
	return false
end

local function foliageBlocks(center, size)
	-- CanQuery is often off on leaf meshes, so the overlap query never sees them.
	local pad = math.max(size.X, size.Z) * 0.5
	local halfY = size.Y * 0.5
	for _, part in ipairs(foliage) do
		if part.Parent and part.CFrame and part.CFrame.PointToObjectSpace and part.Size then
			local localPoint = part.CFrame:PointToObjectSpace(center)
			if math.abs(localPoint.X) <= part.Size.X * 0.5 + pad
				and math.abs(localPoint.Y) <= part.Size.Y * 0.5 + halfY
				and math.abs(localPoint.Z) <= part.Size.Z * 0.5 + pad then
				return true
			end
		end
	end
	return false
end

local function blocked(position, coinSize, grassPart)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {coinsFolder, grassPart}
	local size = Vector3.new(coinSize.X + CLEAR_PADDING, math.max(coinSize.Y, 2) + 4, coinSize.Z + CLEAR_PADDING)
	local center = position + Vector3.new(0, size.Y * 0.5, 0)
	if foliageBlocks(center, size) then return true end
	local hits = Workspace:GetPartBoundsInBox(CFrame.new(center), size, params)
	for _, hit in ipairs(hits) do
		if hit:IsA("BasePart") and not isGrass(hit) and not characterOf(hit) then return true end
	end
	return false
end

local function surfacePoint(part)
	local size = part.Size
	local localPoint = Vector3.new((math.random() - 0.5) * size.X * 0.9, size.Y * 0.5 + 40, (math.random() - 0.5) * size.Z * 0.9)
	local origin = part.CFrame:PointToWorldSpace(localPoint)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {part}
	params.IgnoreWater = true
	local hit = Workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	if not hit or not hit.Position or not hit.Normal or hit.Normal.Y < 0.7 then return nil end
	return hit.Position
end

local function prepare(copy)
	local parts = {}
	if copy:IsA("BasePart") then parts[1] = copy end
	for _, item in ipairs(copy:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = true
			parts[#parts + 1] = item
		end
	end
	return parts
end

local function removeCoin(coin)
	for index, other in ipairs(alive) do
		if other == coin then
			table.remove(alive, index)
			break
		end
	end
	if coin.model and coin.model.Parent then coin.model:Destroy() end
end

local function resolveDoubleId()
	if doubleId ~= nil then return doubleId end
	doubleId = 0
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local catalogModule = modules and modules:FindFirstChild("ShopCatalog")
	if not catalogModule then return doubleId end
	local ok, catalog = pcall(require, catalogModule)
	if not ok or type(catalog) ~= "table" or type(catalog.Passes) ~= "table" then return doubleId end
	for _, pass in ipairs(catalog.Passes) do
		if pass.name == "2x Coins" and type(pass.id) == "number" and pass.id > 0 then
			doubleId = math.floor(pass.id)
			return doubleId
		end
	end
	return doubleId
end

local function payout(player)
	if resolveDoubleId() > 0 and ownsDouble[player.UserId] then return 2 end
	return 1
end

local function publishPayout(player)
	if player and player.SetAttribute then player:SetAttribute("MapCoinPayout", payout(player)) end
end

local function refreshDouble(player)
	if not player then return end
	if resolveDoubleId() ~= 0 then
		local marketplace = game:GetService("MarketplaceService")
		local ok, owns = pcall(function()
			return marketplace:UserOwnsGamePassAsync(player.UserId, doubleId)
		end)
		if ok and player.Parent == Players then ownsDouble[player.UserId] = owns == true end
	end
	publishPayout(player)
end

local function grantPickup(player)
	local grant = ReplicatedStorage:FindFirstChild("GrantCoins")
	if not grant or not grant.Invoke then return nil end
	local amount = payout(player)
	local ok, paid = pcall(function()
		return grant:Invoke(player.UserId, amount, "coin_" .. HttpService:GenerateGUID(false))
	end)
	if ok and paid == true then return amount end
	return nil
end

local function collect(coin, player)
	if coin.claimed or not player or player.Parent ~= Players then return false end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then return false end
	coin.claimed = true
	local amount = grantPickup(player)
	if not amount then
		coin.claimed = false
		return false
	end
	local model = coin.model
	local zone = coin.quadrant
	removeCoin(coin)
	delayed[#delayed + 1] = {at = os.clock() + RESPAWN_SECONDS, quadrant = zone}
	table.sort(delayed, function(a, b) return a.at < b.at end)
	if collectRemote then collectRemote:FireClient(player, model, amount) end
	return true
end

local function withinReach(player, coin)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or coin.claimed then return false end
	local targets = {coin.position}
	if coin.model and coin.model.GetPivot then
		local pivot = coin.model:GetPivot()
		if pivot and pivot.Position then targets[#targets + 1] = pivot.Position end
	end
	for _, point in ipairs(targets) do
		local offset = root.Position - point
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= REACH and math.abs(offset.Y) <= REACH_Y then
			return true
		end
	end
	return false
end

local function hookTouches(coin, parts)
	for _, part in ipairs(parts) do
		if part.Touched then
			part.Touched:Connect(function(hit)
				local character = characterOf(hit)
				local player = character and Players:GetPlayerFromCharacter(character)
				if player then collect(coin, player) end
			end)
		end
	end
end

local function place(copy, surface)
	local pivot = copy:GetPivot()
	local boxCF, boxSize = measure(copy)
	local bottom = boxCF.Position.Y - boxSize.Y * 0.5
	local shift = Vector3.new(surface.X - boxCF.Position.X, surface.Y + 0.2 - bottom, surface.Z - boxCF.Position.Z)
	copy:PivotTo(pivot + shift)
	local placed = copy:GetPivot().Position
	return Vector3.new(surface.X, placed.Y, surface.Z), boxSize
end

local function quadrantOf(position)
	-- Height is ignored. The cross of X = 0 and Z = 0 splits the map into four zones.
	local east = position.X >= 0
	local north = position.Z >= 0
	if east and north then return 1 end
	if not east and north then return 2 end
	if east and not north then return 3 end
	return 4
end

local function quadrantCounts()
	local counts = {0, 0, 0, 0}
	for _, coin in ipairs(alive) do
		local index = coin.quadrant
		if index and counts[index] then counts[index] += 1 end
	end
	return counts
end

local function openQuadrants(prefer)
	local counts = quadrantCounts()
	local open = {}
	for index = 1, 4 do
		if counts[index] < ZONE_CAP then open[#open + 1] = index end
	end
	table.sort(open, function(a, b)
		if prefer and a ~= b then
			if a == prefer then return true end
			if b == prefer then return false end
		end
		if counts[a] ~= counts[b] then return counts[a] < counts[b] end
		return a < b
	end)
	return open
end

local function spawnOne(prefer)
	if not template then return false end
	local _, coinSize = measure(template)
	for _, quadrant in ipairs(openQuadrants(prefer)) do
		for _ = 1, ATTEMPTS do
			local part = pickGrass()
			local surface = part and surfacePoint(part)
			if surface and quadrantOf(surface) == quadrant and not tooClose(surface) and not blocked(surface, coinSize, part) then
				local copy = template:Clone()
				local position = place(copy, surface)
				copy.Parent = coinsFolder
				local coin = {model = copy, position = position, claimed = false, quadrant = quadrant}
				alive[#alive + 1] = coin
				hookTouches(coin, prepare(copy))
				return true
			end
		end
	end
	return false
end

local function canSpawn(now)
	if #alive >= MAX_COINS then return false end
	local counts = quadrantCounts()
	local room = false
	for index = 1, 4 do
		if counts[index] < ZONE_CAP then room = true break end
	end
	if not room then return false end
	if #delayed > 0 then return delayed[1].at <= now end
	return unspawned > 0
end

local function noteSpawn(now)
	if #delayed > 0 and delayed[1].at <= now then
		table.remove(delayed, 1)
	elseif unspawned > 0 then
		unspawned -= 1
	end
end

local function collectNear()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			for index = #alive, 1, -1 do
				local coin = alive[index]
				local offset = root.Position - coin.position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 3.5 and math.abs(offset.Y) <= 6 then
					collect(coin, player)
				end
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if not template or not template.Parent then
		template = findTemplate()
		if not template then
			if not warnedTemplate then
				warnedTemplate = true
				warn("[MapCoins] Add a Model named Coin to ServerStorage")
			end
			return
		end
	end
	collectNear()
	if now < retryAt then return end
	refreshGrass(now)
	local spawned = 0
	local prefer = (#delayed > 0 and delayed[1].at <= now) and delayed[1].quadrant or nil
	while spawned < SPAWNS_PER_STEP and canSpawn(now) do
		if not spawnOne(prefer) then
			retryAt = now + RETRY_SECONDS
			break
		end
		noteSpawn(now)
		prefer = (#delayed > 0 and delayed[1].at <= now) and delayed[1].quadrant or nil
		spawned += 1
	end
end)

local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "Remotes"
	remoteFolder.Parent = ReplicatedStorage
end
collectRemote = remoteFolder:FindFirstChild("CollectMapCoin")
if not collectRemote then
	collectRemote = Instance.new("RemoteEvent")
	collectRemote.Name = "CollectMapCoin"
	collectRemote.Parent = remoteFolder
end
collectRemote.OnServerEvent:Connect(function(player, model)
	if not player or player.Parent ~= Players then return end
	for _, coin in ipairs(alive) do
		if coin.model == model then
			if withinReach(player, coin) then
				if not collect(coin, player) then collectRemote:FireClient(player, model, false) end
			else
				collectRemote:FireClient(player, model, false)
			end
			return
		end
	end
	collectRemote:FireClient(player, model, false)
end)

local function watchPass(player)
	if task and task.spawn then
		task.spawn(refreshDouble, player)
	else
		refreshDouble(player)
	end
end
if Players.PlayerAdded then Players.PlayerAdded:Connect(watchPass) end
for _, player in ipairs(Players:GetPlayers()) do watchPass(player) end
if Players.PlayerRemoving then
	Players.PlayerRemoving:Connect(function(player)
		ownsDouble[player.UserId] = nil
	end)
end
if resolveDoubleId() > 0 then
	game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
		if id == doubleId and player and purchased then
			ownsDouble[player.UserId] = true
			publishPayout(player)
		end
	end)
end

local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local player = Players.LocalPlayer
local initialized = setmetatable({}, {__mode = "k"})
local lastThrow = -math.huge

local function fire(tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if tool.Parent ~= character or not camera or not humanoid or humanoid.Health <= 0 then return end
	if humanoid:GetAttribute("Ragdolled") or UIS:GetFocusedTextBox() then return end
	local now = os.clock()
	if now - lastThrow < Config.bombCooldown then return end
	lastThrow = now
	local point = UIS.TouchEnabled and camera.ViewportSize / 2 or UIS:GetMouseLocation()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	Remotes.ThrowBomb:FireServer(result and result.Position or ray.Origin + ray.Direction * 1000)
end

local function watch(tool)
	if not tool:IsA("Tool") or tool.Name ~= Config.bombToolName or initialized[tool] then return end
	initialized[tool] = true
	tool.Activated:Connect(function() fire(tool) end)
end

local backpackConnection, characterConnection
local function spawned(character)
	if backpackConnection then backpackConnection:Disconnect() end
	if characterConnection then characterConnection:Disconnect() end
	local backpack = player:WaitForChild("Backpack")
	local ordered = false
	local function inventoryChanged(child)
		watch(child)
		if ordered or player.Character ~= character then return end
		local grapple = backpack:FindFirstChild(Config.toolName)
		local bomb = backpack:FindFirstChild(Config.bombToolName)
		if not grapple or not bomb then return end
		ordered = true
		-- Initialize the native hotbar as grapple=1, bomb=2 once per spawn.
		-- No numeric key overrides, and no reordering on ordinary equips.
		local others = {}
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item ~= grapple and item ~= bomb then table.insert(others, item) end
		end
		local staging = Instance.new("Folder")
		staging.Parent = Storage
		grapple.Parent, bomb.Parent = staging, staging
		for _, item in ipairs(others) do item.Parent = staging end
		grapple.Parent = backpack
		bomb.Parent = backpack
		for _, item in ipairs(others) do item.Parent = backpack end
		staging:Destroy()
	end
	backpackConnection = backpack.ChildAdded:Connect(inventoryChanged)
	characterConnection = character.ChildAdded:Connect(watch)
	for _, child in ipairs(backpack:GetChildren()) do inventoryChanged(child) end
	for _, child in ipairs(character:GetChildren()) do watch(child) end
end
player.CharacterAdded:Connect(spawned)
if player.Character then task.spawn(spawned, player.Character) end

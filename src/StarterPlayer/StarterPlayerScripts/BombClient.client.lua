local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local player = Players.LocalPlayer
local initialized = setmetatable({}, {__mode = "k"})
local lastRequest = -math.huge
local lastPushRequest = -math.huge
local function push(tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tool.Parent ~= character or not tool.Enabled or not humanoid or humanoid.Health <= 0 then return end
	if humanoid:GetAttribute("GrapplePhysicsLocked") or UIS:GetFocusedTextBox() then return end
	if os.clock() - lastPushRequest < 0.15 then return end
	lastPushRequest = os.clock()
	Remotes.UsePush:FireServer()
end

-- Handle-free abilities also accept direct mouse input, including while
-- ragdolled when Roblox may not deliver Tool.Activated.
UIS.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.pushToolName)
	if tool then push(tool) end
end)

local function fire(tool, aimPosition)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if tool.Parent ~= character or not camera or not humanoid or humanoid.Health <= 0 then return end
	if not tool.Enabled or tool:GetAttribute("BombCoolingDown") then return end
	if humanoid:GetAttribute("CapsuleLocked") or UIS:GetFocusedTextBox() then return end
	local now = os.clock()
	-- Only debounce input locally. The server starts the real cooldown on an
	-- accepted throw, so a rejected request cannot strand the tool for six seconds.
	if now - lastRequest < 0.15 then return end
	lastRequest = now
	local point = aimPosition or UIS:GetMouseLocation()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	Remotes.ThrowBomb:FireServer(result and result.Position or ray.Origin + ray.Direction * 1000)
end

local function watch(tool)
	if not tool:IsA("Tool") or (tool.Name ~= Config.bombToolName and tool.Name ~= Config.pushToolName) or initialized[tool] then return end
	initialized[tool] = true
	tool.Activated:Connect(function()
		if tool.Name == Config.pushToolName then push(tool) return end
		-- Mobile aim arrives through TouchTapInWorld with the firing finger.
		if not UIS.TouchEnabled then
			if tool.Name == Config.pushToolName then push(tool) else fire(tool) end
		end
	end)
end

UIS.TouchTapInWorld:Connect(function(touchPositions, processed)
	if processed or not UIS.TouchEnabled then return end
	local character = player.Character
	local pushTool = character and character:FindFirstChild(Config.pushToolName)
	if pushTool then push(pushTool) return end
	local tool = character and character:FindFirstChild(Config.bombToolName)
	-- Roblox supplies one Vector2 here on current mobile clients; accept the
	-- older list form as well.
	local position = typeof(touchPositions) == "Vector2" and touchPositions or touchPositions[#touchPositions]
	if tool and position then fire(tool, position) end
end)

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
		local pushTool = backpack:FindFirstChild(Config.pushToolName)
		if not grapple or not pushTool or not bomb then return end
		ordered = true
		-- Initialize the native hotbar as grapple=1, push=2, bomb=3 once per spawn.
		-- No numeric key overrides, and no reordering on ordinary equips.
		local others = {}
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item ~= grapple and item ~= pushTool and item ~= bomb then table.insert(others, item) end
		end
		local staging = Instance.new("Folder")
		staging.Parent = Storage
		grapple.Parent, pushTool.Parent, bomb.Parent = staging, staging, staging
		for _, item in ipairs(others) do item.Parent = staging end
		grapple.Parent = backpack
		pushTool.Parent = backpack
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

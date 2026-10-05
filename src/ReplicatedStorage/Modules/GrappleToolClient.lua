-- Also safe for existing Tool LocalScripts to call: one controller per tool.
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Remotes = require(storage.Modules:WaitForChild("GrappleRemotes"))
local M = {}
local initialized = setmetatable({}, {__mode = "k"})
local lastShot = -math.huge
function M.Fire(tool, centerAim)
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not camera or not tool or tool.Parent ~= character or not humanoid or humanoid.Health <= 0 then return end
	if humanoid:GetAttribute("GrapplePhysicsLocked") or UIS:GetFocusedTextBox() then return end
	local now = os.clock()
	-- Tool.Activated and the mouse fallback can report the same physical click.
	if now - lastShot < 0.1 then return end
	lastShot = now
	local ray
	if centerAim then
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	else
		local position = UIS:GetMouseLocation()
		-- GetMouseLocation uses raw viewport pixels. ScreenPointToRay would
		-- apply the top-bar inset again and aim below the clicked pixel.
		ray = camera:ViewportPointToRay(position.X, position.Y)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local result = workspace:Raycast(ray.Origin, ray.Direction * Config.maxRopeLength, params)
	local target = result and result.Position or ray.Origin + ray.Direction * Config.maxRopeLength
	Remotes.FireGrapple:FireServer(target, camera.CFrame.Position)
end
function M.Init(tool)
	if not tool or not tool:IsA("Tool") or initialized[tool] then return end
	initialized[tool] = true
	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local connections = {}
	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end
	local function cursor()
		if not Config.CustomCursorsEnabled then return end
		if tool.Parent ~= player.Character then mouse.Icon = "" return end
		mouse.Icon = tool:GetAttribute("HasGrappled") and Config.GrappleInUseIcon
			or tool:GetAttribute("InCooldown") and Config.MouseObstructedIcon or Config.CustomCursorIcon
	end
	connect(tool.Equipped, cursor)
	connect(tool.Unequipped, function() if Config.CustomCursorsEnabled then mouse.Icon = "" end end)
	connect(tool.Activated, function() M.Fire(tool) end)
	connect(UIS.InputBegan, function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			M.Fire(tool)
		end
	end)
	for _, attribute in ipairs({"InCooldown", "InUse", "HasGrappled"}) do
		connect(tool:GetAttributeChangedSignal(attribute), cursor)
	end
	connect(tool.Destroying, function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		if tool.Parent == player.Character and Config.CustomCursorsEnabled then mouse.Icon = "" end
		initialized[tool] = nil
	end)
	cursor()
end
return M

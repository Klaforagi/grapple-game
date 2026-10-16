-- Also safe for existing Tool LocalScripts to call: one controller per tool.
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Config = require(storage:WaitForChild("GrappleConfig"))
local Remotes = require(storage.Modules:WaitForChild("GrappleRemotes"))
local M = {}
local initialized = setmetatable({}, {__mode = "k"})
local lastShot = -math.huge
function M.Fire(tool, aimPosition)
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
	if aimPosition == true then
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	elseif aimPosition then
		ray = camera:ViewportPointToRay(aimPosition.X, aimPosition.Y)
	else
		local position = UIS:GetMouseLocation()
		-- GetMouseLocation uses raw viewport pixels. ScreenPointToRay would
		-- apply the top-bar inset again and aim below the clicked pixel.
		ray = camera:ViewportPointToRay(position.X, position.Y)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {character}
	params.FilterDescendantsInstances = ignored
	-- The hook still stops at its upgrade range. The aim point stays on the
	-- clicked surface so a far ground shot keeps that direction.
	local aimDistance = Config.aimRayLength or 100000
	local result
	for _ = 1, 64 do
		result = workspace:Raycast(ray.Origin, ray.Direction * aimDistance, params)
		if not result or result.Instance.Name ~= "InvisPart" then break end
		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end
	if result and result.Instance.Name == "InvisPart" then result = nil end
	local target = result and result.Position or ray.Origin + ray.Direction * aimDistance
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
	connect(tool.Activated, function()
		-- On phones, TouchTapInWorld below provides the actual firing finger.
		if not UIS.TouchEnabled then M.Fire(tool) end
	end)
	connect(UIS.InputBegan, function(input, processed)
		if not UIS.TouchEnabled and not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			M.Fire(tool)
		end
	end)
	connect(UIS.TouchTapInWorld, function(touchPositions, processed)
		if processed or not UIS.TouchEnabled or tool.Parent ~= player.Character then return end
		-- TouchTapInWorld currently supplies one Vector2. Some older input
		-- paths supply a list, so retain support for both forms.
		local position = typeof(touchPositions) == "Vector2" and touchPositions or touchPositions[#touchPositions]
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		local hud = playerGui and playerGui:FindFirstChild("GrappleHUD")
		local reel = hud and hud:FindFirstChild("ReelControls")
		if position and reel and reel.Visible then
			local origin, size = reel.AbsolutePosition, reel.AbsoluteSize
			if position.X >= origin.X and position.X <= origin.X + size.X
				and position.Y >= origin.Y and position.Y <= origin.Y + size.Y then return end
		end
		if position then M.Fire(tool, position) end
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

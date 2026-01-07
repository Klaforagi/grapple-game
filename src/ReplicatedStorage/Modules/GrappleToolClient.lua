-- ModuleScript: ReplicatedStorage.Modules.GrappleToolClient
-- Client-side behavior for the grapple tool.
-- Call: require(...).Init(tool)

local M = {}

function M.Init(tool: Tool)
	----------------------------------------------------------------
	-- PLAYER & TOOL REFERENCES
	----------------------------------------------------------------

	local plr = game:GetService("Players").LocalPlayer
	if not plr then
		warn("[GrappleToolClient] LocalPlayer missing")
		return
	end

	if not tool or not tool:IsA("Tool") then
		warn("[GrappleToolClient] Init expected a Tool, got:", tool)
		return
	end

	-- Prevent double-initializing if the Tool gets reparented or re-run
	if tool:GetAttribute("GrappleToolClientInit") then
		return
	end
	tool:SetAttribute("GrappleToolClientInit", true)

	----------------------------------------------------------------
	-- SERVICES & INPUT
	----------------------------------------------------------------

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UserInputService = game:GetService("UserInputService")
	local workspace = game:GetService("Workspace")

	-- Mouse used for aiming the grapple
	local mouse = plr:GetMouse()

	-- Camera used to convert screen position into a world ray
	local camera = workspace.CurrentCamera

	----------------------------------------------------------------
	-- MODULES & CONFIG
	----------------------------------------------------------------

	-- RemoteEvents used to communicate with the server
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Grapple configuration (icons, tool name, settings)
	local GrappleProperties = require(ReplicatedStorage:WaitForChild("GrappleConfig"))

	----------------------------------------------------------------
	-- STATE
	----------------------------------------------------------------

	local equipped = false
	local connections = {}

	local function connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(connections, c)
		return c
	end

	local function cleanupConnections()
		for _, c in ipairs(connections) do
			if c and c.Disconnect then
				c:Disconnect()
			end
		end
		table.clear(connections)
	end

	----------------------------------------------------------------
	-- CURSOR ICON HANDLER
	----------------------------------------------------------------

	local function updateCursorIcon(enable)
		if not GrappleProperties.CustomCursorsEnabled then
			return
		end

		if enable then
			if equipped then
				if tool:GetAttribute("HasGrappled") then
					mouse.Icon = GrappleProperties.GrappleInUseIcon
				else
					if tool:GetAttribute("InCooldown") then
						mouse.Icon = GrappleProperties.MouseObstructedIcon
					else
						mouse.Icon = GrappleProperties.CustomCursorIcon
					end
				end
			end
		else
			mouse.Icon = ""
		end
	end

	----------------------------------------------------------------
	-- TOOL EQUIP / UNEQUIP
	----------------------------------------------------------------

	connect(tool.Equipped, function()
		equipped = true
		updateCursorIcon(true)
	end)

	connect(tool.Unequipped, function()
		updateCursorIcon(false)
		equipped = false
	end)

	----------------------------------------------------------------
	-- TOOL ACTIVATION (CLICK)
	----------------------------------------------------------------

	connect(tool.Activated, function()
		-- CurrentCamera can be nil briefly during camera transitions
		camera = workspace.CurrentCamera
		if not camera then return end

		local screenRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local _hitPos = screenRay.Origin + screenRay.Direction * 1000 -- fallback (kept for parity)

		Remotes:WaitForChild("FireGrapple"):FireServer(mouse.Hit.Position, camera.CFrame.Position)
	end)

	----------------------------------------------------------------
	-- ATTRIBUTE CHANGE LISTENERS
	----------------------------------------------------------------

	connect(tool:GetAttributeChangedSignal("InCooldown"), function()
		updateCursorIcon(true)
	end)

	connect(tool:GetAttributeChangedSignal("InUse"), function()
		updateCursorIcon(not plr.Backpack:FindFirstChild(GrappleProperties.toolName))
	end)

	connect(tool:GetAttributeChangedSignal("HasGrappled"), function()
		updateCursorIcon(not plr.Backpack:FindFirstChild(GrappleProperties.toolName))
	end)

	----------------------------------------------------------------
	-- BACKPACK SAFETY HANDLING
	----------------------------------------------------------------

	connect(plr.Backpack.ChildAdded, function(child)
		if child.Name == GrappleProperties.toolName then
			if tool:GetAttribute("InUse") or tool:GetAttribute("HasGrappled") then
				child.Parent = plr.Character
			end
		end
	end)

	local function bindCharacter(char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
		if not hum then return end

		connect(char.ChildAdded, function(child)
			if child.Name == GrappleProperties.toolName then
				-- NOTE: HasTag requires CollectionService tags; if you intended Humanoid attributes, adjust this.
				-- Keeping your original logic:
				if hum:HasTag("Ragdoll") then
					child.Parent = plr.Backpack
				end
			end
		end)
	end

	if plr.Character then
		bindCharacter(plr.Character)
	end
	connect(plr.CharacterAdded, bindCharacter)

	----------------------------------------------------------------
	-- INPUT: TOGGLE WALL MODE
	----------------------------------------------------------------

	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if not equipped then return end

		if input.KeyCode == GrappleProperties.toggleWallMode then
			Remotes:WaitForChild("ToggleWallMode"):FireServer()
		end
	end)

	----------------------------------------------------------------
	-- OPTIONAL: if tool is destroyed, clean connections (safety)
	----------------------------------------------------------------
	connect(tool.AncestryChanged, function(_, parent)
		if parent == nil then
			cleanupConnections()
		end
	end)
end

return M

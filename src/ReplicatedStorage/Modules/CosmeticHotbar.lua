local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Palettes = require(ReplicatedStorage:WaitForChild("ItemColors"))
local Catalog = require(script.Parent:WaitForChild("CosmeticCatalog"))
local Style = require(script.Parent:WaitForChild("CosmeticStyle"))
local RagdollToolClient = require(script.Parent:WaitForChild("RagdollToolClient"))

local Hotbar = {}
local ORDER = {Config.toolName, Config.pushToolName, Config.bombToolName}
local KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

local function make(class, parent, properties)
	local object = Instance.new(class)
	for property, value in pairs(properties) do object[property] = value end
	object.Parent = parent
	return object
end

function Hotbar.Mount(screen, player, hidden)
	local bar = make("Frame", screen, {
		Name = "CosmeticHotbar", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(0, 64),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10,
	})
	local slots = {}
	local backpack = player:WaitForChild("Backpack")
	local characterConnections = {}
	local knownOrder = setmetatable({}, {__mode = "k"})
	local nextOrder = 0
	local scheduled = false

	local function selectionColor(kind)
		local name = player:GetAttribute(Catalog.Attributes[kind]) or Catalog.Defaults[kind]
		return name, Palettes.Swatches[kind][name] or Palettes[kind][name] or Color3.new(1, 1, 1)
	end

	local function selectSlot(index)
		if hidden() then return end
		local tool = slots[index]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not tool or not humanoid or humanoid.Health <= 0 then return end
		if humanoid:GetAttribute("Ragdolled") == true then
			RagdollToolClient.Select(tool.Name)
		elseif tool.Parent == character then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(tool)
		end
	end

	local function refresh()
		for _, child in ipairs(bar:GetChildren()) do child:Destroy() end
		local all, byName, extras = {}, {}, {}
		local function collect(container)
			if not container then return end
			for _, child in ipairs(container:GetChildren()) do
				if not child:IsA("Tool") then continue end
				if not knownOrder[child] then nextOrder += 1 knownOrder[child] = nextOrder end
				byName[child.Name] = byName[child.Name] or child
				if child.Name ~= ORDER[1] and child.Name ~= ORDER[2] and child.Name ~= ORDER[3] then
					table.insert(extras, child)
				end
			end
		end
		collect(backpack)
		collect(player.Character)
		for _, name in ipairs(ORDER) do if byName[name] then table.insert(all, byName[name]) end end
		table.sort(extras, function(a, b) return knownOrder[a] < knownOrder[b] end)
		for _, tool in ipairs(extras) do table.insert(all, tool) end
		for index = 1, math.min(#all, 10) do slots[index] = all[index] end
		for index = #all + 1, 10 do slots[index] = nil end
		local count = math.min(#all, 10)
		bar.Size = UDim2.fromOffset(count * 58 + math.max(0, count - 1) * 6, 64)
		bar.Visible = count > 0 and not hidden()
		for index = 1, count do
			local tool = all[index]
			local selected = tool.Parent == player.Character
			local button = make("ImageButton", bar, {
				Name = "Slot" .. index, Image = "", AutoButtonColor = true,
				Position = UDim2.fromOffset((index - 1) * 64, 4), Size = UDim2.fromOffset(58, 58),
				BorderSizePixel = 0, ZIndex = 11,
			})
			local stroke = Style.Surface(button, selected and Style.Header or Style.Slot, 7)
			stroke.Color = selected and Style.Accent or Style.Ink
			stroke.Thickness = selected and 3 or 2
			local kind = tool.Name == Config.toolName and "Gun" or tool.Name == Config.bombToolName and "Bomb" or nil
			if kind then
				local name, color = selectionColor(kind)
				local art = make("Frame", button, {
					Name = "Art", Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(46, 45),
					BackgroundTransparency = 1, ZIndex = 12,
				})
				Style.Icon(art, {Kind = kind, Name = name, Color = color})
				if kind == "Gun" then
					local ropeName, ropeColor = selectionColor("Rope")
					local badge = make("Frame", button, {
						Name = "RopeBadge", Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(19, 19),
						BackgroundColor3 = Style.Slot, BorderSizePixel = 0, ZIndex = 14,
					})
					make("UICorner", badge, {CornerRadius = UDim.new(0, 4)})
					local rope = Style.Icon(badge, {Kind = "Rope", Name = ropeName, Color = ropeColor})
					rope.ZIndex = 15
				end
			elseif tool.TextureId ~= "" then
				make("ImageLabel", button, {
					Name = "Art", Position = UDim2.fromOffset(7, 5), Size = UDim2.fromOffset(44, 44),
					Image = tool.TextureId, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, ZIndex = 12,
				})
			else
				local title = make("TextLabel", button, {
					Name = "Art", Position = UDim2.fromOffset(3, 5), Size = UDim2.fromOffset(52, 43),
					BackgroundTransparency = 1, Text = tool.Name, TextWrapped = true,
					Font = Enum.Font.GothamBold, TextColor3 = Style.Text, TextSize = 10, ZIndex = 12,
				})
				title.TextStrokeColor3, title.TextStrokeTransparency = Style.Ink, 0.25
			end
			local number = make("TextLabel", button, {
				Name = "Number", Position = UDim2.fromOffset(3, 42), Size = UDim2.fromOffset(17, 13),
				BackgroundTransparency = 1, Text = tostring(index % 10), TextColor3 = Style.Text,
				Font = Enum.Font.GothamBold, TextSize = 11, ZIndex = 16,
			})
			number.TextStrokeColor3, number.TextStrokeTransparency = Style.Ink, 0.2
			button.Activated:Connect(function() selectSlot(index) end)
		end
	end

	local function scheduleRefresh()
		if scheduled then return end
		scheduled = true
		task.defer(function()
			scheduled = false
			refresh()
		end)
	end

	local backpackConnections = {}
	local function watchBackpack(nextBackpack)
		for _, connection in ipairs(backpackConnections) do connection:Disconnect() end
		table.clear(backpackConnections)
		backpack = nextBackpack
		table.insert(backpackConnections, backpack.ChildAdded:Connect(scheduleRefresh))
		table.insert(backpackConnections, backpack.ChildRemoved:Connect(scheduleRefresh))
		scheduleRefresh()
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchBackpack(child) end
	end)
	watchBackpack(backpack)
	local function watchCharacter(character)
		for _, connection in ipairs(characterConnections) do connection:Disconnect() end
		table.clear(characterConnections)
		if character then
			table.insert(characterConnections, character.ChildAdded:Connect(scheduleRefresh))
			table.insert(characterConnections, character.ChildRemoved:Connect(scheduleRefresh))
		end
		scheduleRefresh()
	end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function() watchCharacter(nil) end)
	watchCharacter(player.Character)
	for _, attribute in ipairs({"GrappleGunColor", "GrappleRopeColor", "BombColor"}) do
		player:GetAttributeChangedSignal(attribute):Connect(scheduleRefresh)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		local index = KEYS[input.KeyCode]
		if index then
			selectSlot(index)
		elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight then
			local count = #slots
			if count == 0 then return end
			local equipped = 0
			for slotIndex, tool in ipairs(slots) do
				if tool.Parent == player.Character then equipped = slotIndex break end
			end
			local direction = input.KeyCode == Enum.KeyCode.DPadRight and 1 or -1
			selectSlot(((equipped - 1 + direction) % count) + 1)
		end
	end)
	return function()
		bar.Visible = #slots > 0 and not hidden()
	end
end

return Hotbar

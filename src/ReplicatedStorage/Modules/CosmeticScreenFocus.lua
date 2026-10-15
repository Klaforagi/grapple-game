-- Suspend other screen GUIs while the station owns the screen. Leave the world
-- and camera inputs alone; the transparent root never consumes pointer input.
local Focus = {}
function Focus.new(playerGui, owner)
	local active, saved, connections = false, {}, {}
	local function isChat(gui)
		return type(gui.Name) == "string" and string.find(string.lower(gui.Name), "chat", 1, true) ~= nil
	end
	local function watch(gui)
		if gui == owner or isChat(gui) or not gui:IsA("ScreenGui") or connections[gui] then return end
		connections[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if active and gui.Enabled then gui.Enabled = false end
		end)
		if active then saved[gui] = gui.Enabled gui.Enabled = false end
	end
	for _, gui in ipairs(playerGui:GetChildren()) do watch(gui) end
	playerGui.ChildAdded:Connect(watch)
	playerGui.ChildRemoved:Connect(function(gui)
		if connections[gui] then connections[gui]:Disconnect() connections[gui] = nil end
		saved[gui] = nil
	end)
	return function(visible)
		if active == visible then return end
		active = visible
		if active then
			for gui in pairs(connections) do saved[gui] = gui.Enabled gui.Enabled = false end
		else
			for gui, enabled in pairs(saved) do if gui.Parent == playerGui then gui.Enabled = enabled end end
			table.clear(saved)
		end
	end
end
return Focus

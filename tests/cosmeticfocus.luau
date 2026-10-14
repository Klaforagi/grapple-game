return function(source)
	local function signal()
		local entries = {}
		return {Connect = function(_, callback)
			local connection = {callback = callback, connected = true}
			function connection:Disconnect() self.connected = false end
			table.insert(entries, connection)
			return connection
		end, Fire = function(_, ...)
			for _, entry in ipairs(entries) do if entry.connected then entry.callback(...) end end
		end}
	end
	local playerGui = {ChildAdded = signal(), ChildRemoved = signal()}
	local children = {}
	function playerGui:GetChildren() return children end
	local function gui(enabled)
		local changed = signal()
		local object = setmetatable({Parent = playerGui}, {
			__index = function(_, key) if key == "Enabled" then return enabled end end,
			__newindex = function(object, key, value)
				if key == "Enabled" then
					if value ~= enabled then enabled = value changed:Fire() end
				else rawset(object, key, value) end
			end,
		})
		function object:IsA(class) return class == "ScreenGui" end
		function object:GetPropertyChangedSignal() return changed end
		table.insert(children, object)
		return object
	end
	local owner, hud, disabled = gui(true), gui(true), gui(false)
	local setFocus = assert(loadstring(source))().new(playerGui, owner)
	setFocus(true)
	assert(owner.Enabled and not hud.Enabled and not disabled.Enabled, "station did not suppress other GUIs")
	hud.Enabled = true
	assert(not hud.Enabled, "another screen reopened over station")
	local added = gui(true)
	playerGui.ChildAdded:Fire(added)
	assert(not added.Enabled, "new GUI appeared over station")
	setFocus(true)
	setFocus(false)
	assert(hud.Enabled and added.Enabled and not disabled.Enabled, "original visibility was not restored")
	setFocus(true)
	playerGui.ChildRemoved:Fire(added)
	added.Parent = nil
	setFocus(false)
	assert(hud.Enabled and not added.Enabled, "removed GUI was restored")
	print("Cosmetic UI focus: suppression, re-enable attempts, new GUIs and visibility restoration passed")
end

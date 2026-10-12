return function(source)
	local chunk = assert(loadstring(source))
	setfenv(chunk, setmetatable({Enum = {UserInputType = {Touch = "Touch"}}}, {__index = getfenv()}))
	local MobileFlopButton = chunk()
	local function button(visible, parent)
		local result = {Visible = visible, Parent = parent or {}, Position = 1, Size = 2, AnchorPoint = 3, ZIndex = 1}
		result.InputBegan = {}
		function result.InputBegan:Connect(callback)
			local connection = {active = true}
			function connection:Disconnect() self.active = false end
			self.fire = function(input) if connection.active then callback(input) end end
			return connection
		end
		function result:IsA(class) return class == "GuiButton" end
		function result:Clone() return button(self.Visible) end
		function result:Destroy() self.Parent = nil end
		return result
	end
	local flops = 0
	local controller = MobileFlopButton.new(function() flops += 1 end)
	local jump = button(true)
	controller:Update(jump, false)
	assert(not controller.overlay and jump.Visible, "Normal jump created a flop overlay")
	-- Capture hides the native button before the HUD sees ragdoll.
	jump.Visible = false
	controller:Update(jump, true)
	local overlay = controller.overlay
	assert(overlay.Visible and overlay.Parent == jump.Parent and not jump.Visible,
		"Flop must remain available without changing the disabled native jump button")
	overlay.InputBegan.fire({UserInputType = "Touch"})
	assert(flops == 1 and not jump.InputBegan.fire, "Flop input was not isolated from native jump")
	jump.Position, jump.Size = 4, 5
	controller:Update(jump, true)
	assert(controller.overlay == overlay and overlay.Position == 4 and overlay.Size == 5
		and overlay.ZIndex > jump.ZIndex, "Flop did not track the native mobile layout")
	-- Reproduce release ordering: PlayerModule enables jump before HUD recovery.
	jump.Visible = true
	controller:Update(jump, false)
	assert(jump.Visible and not overlay.Parent and not controller.overlay,
		"Grapple recovery overwrote restored jump visibility with stale hidden state")
	overlay.InputBegan.fire({UserInputType = "Touch"})
	assert(flops == 1, "Recovered flop button retained its input listener")
	-- Also support recovery arriving before controls are enabled, without
	-- overriding another system that intentionally still has controls disabled.
	jump.Visible = false
	controller:Update(jump, true)
	controller:Update(jump, false)
	assert(not jump.Visible, "Flop recovery enabled controls owned by another system")
	jump.Visible = true
	controller:Update(jump, false)
	assert(jump.Visible, "Late control restoration was undone")
	-- Repeated captures and native button replacement on respawn.
	for _ = 1, 3 do
		jump.Visible = false
		controller:Update(jump, true)
		jump.Visible = true
		controller:Update(jump, false)
		assert(jump.Visible, "Repeated captures left jump hidden")
	end
	controller:Update(jump, true)
	local oldOverlay = controller.overlay
	local replacement = button(false)
	controller:Update(replacement, true)
	assert(not oldOverlay.Parent and controller.overlay.Parent == replacement.Parent and jump.Visible,
		"Respawn retained the old flop button or changed native visibility")
	local replacementOverlay = controller.overlay
	controller:Update(nil, false)
	assert(not replacementOverlay.Parent and not controller.overlay, "Missing character left a flop overlay")
	print("PASS: mobile jump restoration, release ordering, repeated captures, flop input, and respawn cleanup")
end

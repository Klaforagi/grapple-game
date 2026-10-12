-- Roblox owns JumpButton visibility. A separate overlay supplies flop input
-- during ragdoll without saving/restoring stale state from disabled controls.
local M = {}
M.__index = M

function M.new(onFlop)
	return setmetatable({onFlop = onFlop}, M)
end

function M:Destroy()
	if self.connection then self.connection:Disconnect() end
	if self.overlay then self.overlay:Destroy() end
	self.button, self.overlay, self.connection = nil, nil, nil
end

function M:Update(jump, show)
	if not show or not jump or not jump:IsA("GuiButton") or not jump.Parent then
		self:Destroy()
		return
	end
	if jump ~= self.button or not self.overlay or self.overlay.Parent ~= jump.Parent then
		self:Destroy()
		local overlay = jump:Clone()
		overlay.Name = "GrappleFlopButton"
		overlay.Visible, overlay.Active, overlay.Selectable = true, true, false
		overlay.Parent = jump.Parent
		self.button, self.overlay = jump, overlay
		self.connection = overlay.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then self.onFlop() end
		end)
	end
	-- Keep the native touch layout across orientation and screen-size changes.
	self.overlay.Position = jump.Position
	self.overlay.Size = jump.Size
	self.overlay.AnchorPoint = jump.AnchorPoint
	self.overlay.ZIndex = jump.ZIndex + 1
end

return M

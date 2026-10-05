-- The Studio gun supplies the model; the persistent grapple controllers supply
-- its behavior. Retire embedded controllers before they can reject an equip.
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local M = {}
local prepared = setmetatable({}, {__mode = "k"})

function M.Prepare(tool, server)
	if not tool:IsA("Tool") or tool.Name ~= Config.toolName or prepared[tool] then return end
	prepared[tool] = true
	local function prepare(instance)
		if instance:IsA("Script") or instance:IsA("LocalScript") then
			-- Leave ModuleScripts, the model, and existing joints intact.
			instance.Disabled = true
		elseif server and instance:IsA("BasePart") then
			instance.Anchored, instance.CanCollide, instance.Massless = false, false, true
		end
	end
	for _, instance in ipairs(tool:GetDescendants()) do prepare(instance) end
	local added = tool.DescendantAdded:Connect(prepare)
	tool.Destroying:Connect(function()
		added:Disconnect()
		prepared[tool] = nil
	end)
	if server then
		-- Legacy cooldown scripts may have left activation disabled. The current
		-- server handler owns cooldown validation and the client deduplicates input.
		tool.Enabled = true
		tool.ManualActivationOnly = false
		tool:SetAttribute("GrappleManagedTool", true)
	end
end

return M

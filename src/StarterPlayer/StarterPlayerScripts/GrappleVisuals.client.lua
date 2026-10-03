-- Persistent visual renderer: one render connection, no character clones.
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")
local folder = workspace:WaitForChild("Hitbox")
local templates = storage:FindFirstChild("Templates")
local template = templates and templates:FindFirstChild("Bolt")
local visuals = {}
local function add(hitbox)
	if not hitbox:IsA("BasePart") or visuals[hitbox] then return end
	local visual = template and template:IsA("BasePart") and template:Clone() or Instance.new("Part")
	for _, instance in ipairs(visual:GetDescendants()) do
		if instance:IsA("BaseScript") or instance:IsA("JointInstance") or instance:IsA("Constraint") then instance:Destroy() end
	end
	visual.Name = "VisualGrappleBolt"
	visual.Size = Vector3.new(0.3, 0.3, 1)
	visual.Anchored, visual.CanCollide, visual.CanQuery, visual.CanTouch = true, false, false, false
	visual.CastShadow, visual.Transparency = false, 0
	visual.CFrame = hitbox.CFrame
	visual.Parent = workspace
	visuals[hitbox] = visual
end
folder.ChildAdded:Connect(add)
for _, instance in ipairs(folder:GetChildren()) do add(instance) end
RunService.RenderStepped:Connect(function()
	for hitbox, visual in pairs(visuals) do
		if not hitbox.Parent then visual:Destroy() visuals[hitbox] = nil
		else visual.CFrame = hitbox.CFrame end
	end
end)

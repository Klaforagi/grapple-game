-- Persistent visual renderer: one render connection, no character clones.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")
local Config = require(storage:WaitForChild("GrappleConfig"))
local folder = workspace:WaitForChild("Hitbox")
local templates = storage:FindFirstChild("Templates")
local template = templates and templates:FindFirstChild("Bolt")
local visuals = {}

local function gunBolt(hitbox)
	local ownerName = hitbox.Name:match("^(.-) Hitbox$")
	local owner = ownerName and Players:FindFirstChild(ownerName)
	local tool = owner and owner.Character and owner.Character:FindFirstChild(Config.toolName)
	local bolt = tool and tool:FindFirstChild("Bolt", true)
	return bolt and bolt:IsA("BasePart") and bolt or nil
end

local function copyBoltAppearance(visual, bolt, hitbox)
	visual.Size = bolt.Size
	visual.Color = bolt.Color
	visual.Material = bolt.Material
	visual.MaterialVariant = bolt.MaterialVariant
	visual.Reflectance = bolt.Reflectance
	visual.CastShadow = bolt.CastShadow
	visual.Transparency = hitbox:GetAttribute("BoltVisibleTransparency")
		or bolt:GetAttribute("GrappleBoltVisibleTransparency") or bolt.Transparency
	if visual:IsA("Part") and bolt:IsA("Part") then visual.Shape = bolt.Shape end
	if visual:IsA("MeshPart") and bolt:IsA("MeshPart") then
		pcall(function() visual.TextureID = bolt.TextureID end)
	end
	-- Copy only appearance children. Joints and other physical parts stay on the gun.
	local appearance = {SpecialMesh = true, Decal = true, Texture = true, SurfaceAppearance = true}
	for _, child in ipairs(visual:GetChildren()) do
		if appearance[child.ClassName] then child:Destroy() end
	end
	for _, child in ipairs(bolt:GetChildren()) do
		if appearance[child.ClassName] then
			local copy = child:Clone()
			if copy then copy.Parent = visual end
		end
	end
end

local function createVisual(bolt)
	if bolt and bolt:IsA("MeshPart") then
		-- ApplyMesh transfers the geometry without cloning the gun's welds or constraints.
		local mesh = Instance.new("MeshPart")
		local ok = pcall(function() mesh:ApplyMesh(bolt) end)
		if ok then return mesh end
		mesh:Destroy()
		return Instance.new("Part")
	end
	return template and template:IsA("BasePart") and template:Clone() or Instance.new("Part")
end

local function add(hitbox)
	if not hitbox:IsA("BasePart") or visuals[hitbox] then return end
	local bolt = gunBolt(hitbox)
	local visual = createVisual(bolt)
	for _, instance in ipairs(visual:GetDescendants()) do
		if instance:IsA("BaseScript") or instance:IsA("JointInstance") or instance:IsA("Constraint") then instance:Destroy() end
	end
	visual.Name = "VisualGrappleBolt"
	visual.Anchored, visual.CanCollide, visual.CanQuery, visual.CanTouch = true, false, false, false
	if bolt then
		copyBoltAppearance(visual, bolt, hitbox)
		if bolt:IsA("MeshPart") and not visual:IsA("MeshPart") then
			-- Fallback for clients where ApplyMesh cannot load the source mesh.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = bolt.MeshId
			mesh.TextureId = bolt.TextureID
			mesh.Parent = visual
		end
	else
		visual.Size = Vector3.new(0.3, 0.3, 1)
		visual.CastShadow, visual.Transparency = false, 0
		local boltColor = hitbox:GetAttribute("BoltColor")
		if typeof(boltColor) == "Color3" then
			visual.Color = boltColor
			visual.Material = Enum.Material.Neon
			if visual:IsA("MeshPart") then visual.TextureID = "" end
			for _, instance in ipairs(visual:GetDescendants()) do
				if instance:IsA("SpecialMesh") then instance.TextureId = "" end
			end
		end
	end
	visual.CFrame = hitbox.CFrame
	visual:SetAttribute("RainbowPart", hitbox:GetAttribute("RainbowPart") == true)
	visual:SetAttribute("RainbowPalette", hitbox:GetAttribute("RainbowPalette"))
	visual.Parent = workspace
	visuals[hitbox] = visual
end
folder.ChildAdded:Connect(add)
for _, instance in ipairs(folder:GetChildren()) do add(instance) end
RunService.RenderStepped:Connect(function()
	for hitbox, visual in pairs(visuals) do
		if not hitbox.Parent then visual:Destroy() visuals[hitbox] = nil
		else
			visual.CFrame = hitbox.CFrame
			visual:SetAttribute("RainbowPart", hitbox:GetAttribute("RainbowPart") == true)
			visual:SetAttribute("RainbowPalette", hitbox:GetAttribute("RainbowPalette"))
		end
	end
end)

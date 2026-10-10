local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Studs per second. Use a negative value to reverse the arrows.
-- A Runway part's TextureScrollSpeed attribute overrides this default.
local DEFAULT_SPEED = 25
local textures = {}

local function track(instance)
	if not instance:IsA("Texture") then return end
	local part = instance.Parent
	if not part or not part:IsA("BasePart") or part.Name ~= "Runway" then return end
	textures[instance] = part
end

Workspace.DescendantAdded:Connect(track)
Workspace.DescendantRemoving:Connect(function(instance)
	textures[instance] = nil
end)
for _, instance in ipairs(Workspace:GetDescendants()) do track(instance) end

RunService.RenderStepped:Connect(function(dt)
	for texture, part in pairs(textures) do
		if texture.Parent ~= part or not part:IsDescendantOf(Workspace) then
			textures[texture] = nil
			continue
		end
		local speed = part:GetAttribute("TextureScrollSpeed")
		if typeof(speed) ~= "number" or speed ~= speed or math.abs(speed) == math.huge then
			speed = DEFAULT_SPEED
		end
		-- Wrap by one tile to avoid accumulating huge offsets over long sessions.
		local tileSize = math.max(texture.StudsPerTileV, 0.001)
		texture.OffsetStudsV = (texture.OffsetStudsV + speed * dt) % tileSize
	end
end)

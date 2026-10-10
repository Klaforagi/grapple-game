local Debris = game:GetService("Debris")

local THICKNESS_SCALE = 0.12
local LIFETIME = 8
local M = {}

-- A visual-only corpse with an inert humanoid for classic clothing rendering.
function M.Create(character, groundY)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	local copy = Instance.new("Model")
	copy.Name = character.Name .. "_Flattened"
	copy:SetAttribute("AutoRespawn", false)
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") then
			local archivable = item.Archivable
			item.Archivable = true
			local clothing = item:Clone()
			item.Archivable = archivable
			for _, child in ipairs(clothing:GetChildren()) do child:Destroy() end
			clothing.Parent = copy
		end
	end
	local displayHumanoid = Instance.new("Humanoid")
	local originalHumanoid = character:FindFirstChildOfClass("Humanoid")
	if originalHumanoid then displayHumanoid.RigType = originalHumanoid.RigType end
	displayHumanoid.RequiresNeck = false
	displayHumanoid.BreakJointsOnDeath = false
	displayHumanoid.AutomaticScalingEnabled = false
	displayHumanoid.EvaluateStateMachine = false
	displayHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	displayHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	displayHumanoid.Health = 0
	displayHumanoid.Parent = copy
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
	local laidDown = CFrame.lookAt(Vector3.zero, forward.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
	if torso:IsA("BasePart") and math.abs(torso.CFrame.UpVector.Y) < 0.7 then
		-- A ragdoll's torso can turn independently of its root. If already
		-- lying down, compress the actual world pose instead of laying it down
		-- again. This preserves face-up, face-down, and sideways landings.
		laidDown = root.CFrame.Rotation
	end
	local parts, lowest = {}, math.huge
	local function compressedLength(axis)
		return Vector3.new(axis.X, axis.Y * THICKNESS_SCALE, axis.Z).Magnitude
	end
	for _, original in ipairs(character:GetDescendants()) do
		local accessory = original:FindFirstAncestorOfClass("Accessory")
		if not original:IsA("BasePart") or original == root
			or (original.Parent ~= character and not accessory)
			or original.Transparency >= 1 then continue end
		local archivable = original.Archivable
		original.Archivable = true
		local part = original:Clone()
		original.Archivable = archivable
		-- Keep only appearance data. In particular, never clone tool scripts or
		-- accessory welds referencing the real character into Workspace.
		for _, child in ipairs(part:GetChildren()) do
			if not child:IsA("DataModelMesh") and not child:IsA("Decal")
				and not child:IsA("SurfaceAppearance") then child:Destroy() end
		end
		local pose = laidDown * root.CFrame:ToObjectSpace(original.CFrame)
		local scale = Vector3.new(compressedLength(pose.RightVector),
			compressedLength(pose.UpVector), compressedLength(pose.LookVector))
		part.Size = original.Size * scale
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == Enum.MeshType.FileMesh then mesh.Scale *= scale end
		part.CFrame = CFrame.new(pose.X, pose.Y * THICKNESS_SCALE, pose.Z) * pose.Rotation
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		part.Parent = copy
		local halfHeight = (math.abs(part.CFrame.RightVector.Y) * part.Size.X
			+ math.abs(part.CFrame.UpVector.Y) * part.Size.Y
			+ math.abs(part.CFrame.LookVector.Y) * part.Size.Z) / 2
		lowest = math.min(lowest, part.Position.Y - halfHeight)
		table.insert(parts, part)
	end
	if #parts == 0 then copy:Destroy() return end
	local offset = Vector3.new(root.Position.X, groundY - lowest + 0.03, root.Position.Z)
	for _, part in ipairs(parts) do part.CFrame += offset end
	copy.Parent = workspace
	Debris:AddItem(copy, LIFETIME)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then item.Transparency = 1 end
	end
end

return M

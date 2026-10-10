local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("GrappleConfig"))
local M = {}
function M.CanFlop(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or root.Anchored
		or humanoid:GetAttribute("Ragdolled") ~= true or humanoid:GetAttribute("CapsuleLocked") then return false end
	local tooFast, touchingRunway = false, false
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then
			if part.Anchored then return false end
			if part.AssemblyLinearVelocity.Magnitude > (Config.flopMaxSpeed or 22) then tooFast = true end
			if not touchingRunway and part.Name ~= "HumanoidRootPart" then
				for _, other in ipairs(part:GetTouchingParts()) do
					if other.Name == "Runway" and other.CanCollide and not other:IsDescendantOf(character) then
						touchingRunway = true
						break
					end
				end
			end
		end
	end
	return not tooFast or touchingRunway
end
function M.Apply(character, direction, simulator, variation)
	if not M.CanFlop(character) then return end
	variation = variation or Vector3.new(1, 0, 0)
	if simulator and character:FindFirstChildOfClass("Humanoid"):GetAttribute("RagdollExpectedOwner") ~= simulator.UserId then return end
	local seen = {}
	local root = character:FindFirstChild("HumanoidRootPart")
	local rootAssembly = root.AssemblyRootPart or root
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local tipAxis = Vector3.new(direction.Z, 0, -direction.X)
	for _, part in ipairs(character:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		local assembly = part.AssemblyRootPart or part
		if seen[assembly] or assembly.Anchored then continue end
		seen[assembly] = true
		-- Skip assemblies handed to another simulator while the request travelled.
		if not simulator and assembly:GetNetworkOwner() ~= nil then continue end
		local velocity = assembly.AssemblyLinearVelocity
		local side, flex = 0, 0
		if assembly ~= rootAssembly then
			-- Stable per-part variation bends the joints instead of translating
			-- every limb with identical velocity and preserving the resting pose.
			local seed = 0
			for index = 1, #part.Name do seed += string.byte(part.Name, index) * index end
			side = seed % 2 == 0 and 1 or -1
			flex = (seed % 7 - 3) / 3
		end
		local kick = Config.flopLimbKickSpeed or 7
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
			+ direction * ((Config.flopHorizontalSpeed or 24) + flex * kick)
			+ right * (side * kick)
		if horizontal.Magnitude > 40 then horizontal = horizontal.Unit * 40 end
		local upward = math.clamp(velocity.Y + (Config.flopUpSpeed or 38) + flex * kick, -22, 45)
		assembly.AssemblyLinearVelocity = horizontal + Vector3.new(0, upward, 0)
		local strength = Config.flopSpinSpeed or 30
		-- tipAxis is the shoulder line, so this term rolls stomach to back. The
		-- other axes stay smaller so the flip is not turned into a diagonal spin.
		local spin = tipAxis * (strength * variation.X * (1 + flex * 0.4))
			+ direction * (strength * 0.28 * variation.Y + side * 2.5)
			+ Vector3.new(0, strength * variation.Z, 0)
		local cap = Config.flopSpinCap or 42
		if spin.Magnitude > cap then spin = spin.Unit * cap end
		assembly.AssemblyAngularVelocity = spin
	end
end
return M

return function(t)
	local motion = t.execute(t.source)
	local character, humanoid, root = t.character("FlopTest", Vector3.zero, false)
	local direction = Vector3.new(1, 0, 0)
	assert(not motion.CanFlop(character), "standing player could flop")
	humanoid:SetAttribute("Ragdolled", true)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then part:SetNetworkOwner(nil) end
	end
	assert(motion.CanFlop(character), "slow ragdoll could not flop")
	motion.Apply(character, direction, nil)
	assert(root.AssemblyLinearVelocity.X == 24 and root.AssemblyLinearVelocity.Y == 42,
		"flop did not apply bounded hop")
	assert((character:FindFirstChild("Limb1").AssemblyLinearVelocity - root.AssemblyLinearVelocity).Magnitude > 0,
		"flop left every limb moving in the same rigid pose")
	assert(not motion.CanFlop(character), "strong flop allowed another kick while already moving fast")
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") then part.AssemblyLinearVelocity = Vector3.zero end
	end
	humanoid:SetAttribute("GrapplePhysicsLocked", true)
	assert(motion.CanFlop(character), "grapple lock incorrectly blocked flop")
	motion.Apply(character, direction, nil, Vector3.new(-1, 0.8, 0.2))
	assert(root.AssemblyAngularVelocity.Z > 18 and root.AssemblyAngularVelocity.X > 0
		and root.AssemblyAngularVelocity.Magnitude <= 42.01, "flop variation did not reverse tumble and add bounded roll")
	assert(root.AssemblyLinearVelocity.X <= 40 and root.AssemblyLinearVelocity.Y <= 49,
		"flops stacked into excessive velocity")
	root.AssemblyLinearVelocity = Vector3.new(0, -50, 0)
	assert(not motion.CanFlop(character), "fast falling ragdoll could flop")
	local runway = Instance.new("Part")
	runway.Name, runway.CanCollide = "Runway", true
	character:FindFirstChild("Limb1").TouchingParts = {runway}
	assert(motion.CanFlop(character), "runway contact did not bypass flop speed limit")
	root.Anchored = true
	assert(not motion.CanFlop(character), "runway contact bypassed anchored restriction")
	root.Anchored = false
	humanoid:SetAttribute("CapsuleLocked", true)
	assert(not motion.CanFlop(character), "runway contact bypassed capsule restriction")
	humanoid:SetAttribute("CapsuleLocked", nil)
	character:FindFirstChild("Limb1").TouchingParts = {}
	assert(not motion.CanFlop(character), "leaving runway did not restore flop speed limit")
	runway:Destroy()
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid:SetAttribute("CapsuleLocked", true)
	assert(not motion.CanFlop(character), "capsule captive could flop")
	humanoid:SetAttribute("CapsuleLocked", nil)
	humanoid.Health = 0
	assert(not motion.CanFlop(character), "dead player could flop")
	character:Destroy()
end

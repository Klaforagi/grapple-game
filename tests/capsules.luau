return function(t)
	-- Run the actual capsule server and client scripts with isolated scheduling.
	local instance, methods = t.instance, t.methods
	t.runService.Heartbeat = t.signal()
	t.world.DescendantAdded = t.signal()
	t.env.Enum.ProximityPromptStyle = {Default = "Default"}
	t.env.Enum.Font = {GothamBold = "GothamBold"}
	t.env.UDim2 = {fromScale = function(x, y) return {X = x, Y = y} end,
		fromOffset = function(x, y) return {X = x, Y = y} end}
	function methods:Fire(...) self.Event:Emit(...) end
	function methods:TakeDamage(amount) self.Health -= amount end
	function methods:FindFirstAncestor(name)
		local parent = self.Parent
		while parent do
			if parent.Name == name then return parent end
			parent = parent.Parent
		end
	end
	local owner = instance("Player", "CapsuleTester", t.players)
	owner.UserId = 777
	owner.Character = t.character("CapsuleTester", Vector3.zero, false)
	t.players.LocalPlayer = owner
	local mob, humanoid, root = t.character("CapsuleMob", Vector3.zero, false)
	local tool = instance("Tool", "MobTool", mob)
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 16, 50, 7
	humanoid.MaxHealth = 100
	humanoid:SetAttribute("GrappledBy", owner.UserId)
	local model = instance("Model", "Capsule", t.world)
	local trigger = instance("Part", "Trigger", model)
	trigger.CFrame = {PointToObjectSpace = function(_, point) return point end}
	local platform = instance("Part", "Platform", model)
	instance("Part", "ExitPoint", model)
	platform.CFrame = setmetatable({}, {__mul = function(_, offset) return {placement = offset} end})
	t.execute(t.sources.capsules)
	local prompt = assert(trigger:FindFirstChild("CapsulePrompt"), "Trigger name silently skipped capsule setup")
	assert(prompt.KeyboardKeyCode == t.env.Enum.KeyCode.F, "capsule has wrong key")
	t.execute(t.sources.capsulePrompts)
	t.runService.Heartbeat:Emit(0.1)
	assert(prompt.Enabled, "nearby grappled NPC did not show prompt")
	root.Position = Vector3.new(15, 0, 0)
	t.runService.Heartbeat:Emit(0.1)
	assert(not prompt.Enabled, "distant victim allowed capture prompt")
	prompt.Triggered:Emit(owner)
	assert(not model:GetAttribute("CapsuleOccupied"), "server allowed distant capture")
	root.Position = Vector3.zero
	t.runService.Heartbeat:Emit(0.1)
	prompt.Triggered:Emit(owner)
	assert(model:GetAttribute("CapsuleOccupied") and root.Anchored, "NPC capture failed")
	assert(root.CFrame.placement ~= nil, "capture did not use Platform")
	assert(humanoid:GetAttribute("CapsuleLocked") and humanoid.WalkSpeed == 0 and tool.Parent == nil, "capture did not lock mob")
	t.advance(1)
	t.runService.Heartbeat:Emit(1)
	assert(humanoid.Health == 95, "freezing did not deal 5 damage")
	assert(mob:FindFirstChild("CapsuleHealth").AlwaysOnTop, "health is obscured by capsule walls")
	assert(mob:FindFirstChild("CapsuleHealth"):FindFirstChildOfClass("TextLabel").Text == "CapsuleMob  |  95 / 100 HP", "health display did not follow damage")
	assert(prompt.Enabled and prompt.ActionText == "Save", "NPC rescue prompt missing")
	prompt.Triggered:Emit(owner)
	assert(not model:GetAttribute("CapsuleOccupied") and not root.Anchored, "rescue left capsule occupied")
	assert(not mob:FindFirstChild("CapsuleHealth"), "rescue leaked health display")
	assert(not humanoid:GetAttribute("CapsuleLocked") and humanoid.WalkSpeed == 16 and tool.Parent == mob, "rescue failed to restore mob")
	t.advance(1)
	t.runService.Heartbeat:Emit(1)
	assert(humanoid.Health == 95, "freezing continued after rescue")
	-- A model inserted before its parts/names are ready must be discovered later.
	local late = instance("Model", "Unfinished", t.world)
	local lateTrigger = instance("Part", "TriggerPart", late)
	lateTrigger.CFrame = trigger.CFrame
	late.Name = "Capsule"
	t.runService.Heartbeat:Emit(1)
	assert(lateTrigger:FindFirstChild("CapsulePrompt"), "late-built capsule never registered")
end

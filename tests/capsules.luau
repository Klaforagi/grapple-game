return function(t)
	-- Run the actual capsule server and client scripts with isolated scheduling.
	local instance, methods = t.instance, t.methods
	t.runService.Heartbeat = t.signal()
	t.runService.PreAnimation = t.signal()
	t.world.DescendantAdded = t.signal()
	t.env.Enum.ProximityPromptStyle = {Default = "Default"}
	t.env.Enum.Font = {GothamBold = "GothamBold"}
	t.env.UDim2 = {fromScale = function(x, y) return {X = x, Y = y} end,
		fromOffset = function(x, y) return {X = x, Y = y} end}
	function methods:Fire(...) self.Event:Emit(...) end
	function methods:TakeDamage(amount)
		local wasAlive = self.Health > 0
		self.Health = math.max(0, self.Health - amount)
		if wasAlive and self.Health <= 0 then self.Died:Emit() end
	end
	function methods:GetPlayingAnimationTracks() return self.Tracks or {} end
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
	local animate = instance("LocalScript", "Animate", mob)
	animate.Disabled = false
	local animator = instance("Animator", "Animator", humanoid)
	local stopped = 0
	animator.Tracks = {{Stop = function() stopped += 1 end}}
	local tool = instance("Tool", "MobTool", mob)
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 16, 50, 7
	humanoid.MaxHealth = 100
	humanoid.BreakJointsOnDeath = true
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
	assert(animate.Disabled and stopped > 0, "capture retained idle animation")
	local stoppedBeforeClient = stopped
	animate.Disabled = false
	t.runService.PreAnimation:Emit()
	assert(animate.Disabled and stopped > stoppedBeforeClient, "client did not suppress captive animation")
	t.advance(1)
	t.runService.Heartbeat:Emit(1)
	assert(humanoid.Health == 95, "freezing did not deal 5 damage")
	assert(mob:FindFirstChild("CapsuleHealth").AlwaysOnTop, "health is obscured by capsule walls")
	local healthGui = mob:FindFirstChild("CapsuleHealth")
	local healthText = healthGui:FindFirstChildOfClass("TextLabel")
	assert(healthText.Text == "CapsuleMob", "health display includes numeric health")
	assert(healthText.TextScaled and healthText.BackgroundTransparency == 1,
		"health name does not scale or still has a visible background")
	assert(healthGui.Size.X == 5 and healthGui.Size.Y == 1.15, "health display does not scale in world space")
	assert(prompt.Enabled and prompt.ActionText == "Save", "NPC rescue prompt missing")
	owner.Character:FindFirstChildOfClass("Humanoid"):SetAttribute("GrappledBy", 123)
	t.runService.Heartbeat:Emit(0.1)
	assert(not prompt.Enabled, "grappled rescuer saw capsule prompt")
	prompt.Triggered:Emit(owner)
	assert(model:GetAttribute("CapsuleOccupied"), "grappled rescuer bypassed capsule lock")
	owner.Character:FindFirstChildOfClass("Humanoid"):SetAttribute("GrappledBy", nil)
	prompt.Triggered:Emit(owner)
	assert(not model:GetAttribute("CapsuleOccupied") and not root.Anchored, "rescue left capsule occupied")
	assert(not mob:FindFirstChild("CapsuleHealth"), "rescue leaked health display")
	assert(not humanoid:GetAttribute("CapsuleLocked") and humanoid.WalkSpeed == 16 and tool.Parent == mob, "rescue failed to restore mob")
	t.runService.PreAnimation:Emit()
	assert(not animate.Disabled, "rescue did not restore animation controller")
	assert(humanoid.AutoRotate, "rescue left rotation locked by the capture ragdoll")
	assert(humanoid.BreakJointsOnDeath, "rescue did not restore normal death behavior")
	t.advance(1)
	t.runService.Heartbeat:Emit(1)
	assert(humanoid.Health == 95, "freezing continued after rescue")
	-- A freezing death remains intact and occupies the capsule until the old
	-- NPC is removed as part of its respawn.
	humanoid.Health = 5
	t.runService.Heartbeat:Emit(0.1)
	prompt.Triggered:Emit(owner)
	assert(root.Anchored and not humanoid.BreakJointsOnDeath, "capsule did not prepare intact death")
	t.advance(1)
	t.runService.Heartbeat:Emit(1)
	t.runService.Heartbeat:Emit(0.1)
	assert(humanoid.Health == 0 and model:GetAttribute("CapsuleOccupied")
		and model:GetAttribute("CapsuleWaitingForRespawn"), "death freed capsule before respawn")
	assert(root.Anchored and not prompt.Enabled, "dead captive broke apart or exposed rescue prompt")
	for _, item in ipairs(mob:GetDescendants()) do
		if item:IsA("BasePart") then assert(item.Anchored, "dead captive body was not frozen") end
	end
	mob:Destroy()
	t.runService.Heartbeat:Emit(0.1)
	assert(not model:GetAttribute("CapsuleOccupied"), "capsule did not clear after NPC respawn replacement")
	-- A model inserted before its parts/names are ready must be discovered later.
	local late = instance("Model", "Unfinished", t.world)
	local lateTrigger = instance("Part", "TriggerPart", late)
	lateTrigger.CFrame = trigger.CFrame
	late.Name = "Capsule"
	t.runService.Heartbeat:Emit(1)
	assert(lateTrigger:FindFirstChild("CapsulePrompt"), "late-built capsule never registered")
end

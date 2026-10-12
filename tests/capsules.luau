return function(t)
	-- Run the actual capsule server and client scripts with isolated scheduling.
	local instance, methods = t.instance, t.methods
	local combatHeartbeat = t.runService.Heartbeat
	local originalDelay, scheduled = t.env.task.delay, {}
	t.env.task.delay = function(seconds, callback)
		table.insert(scheduled, {at = t.world:GetServerTimeNow() + seconds, callback = callback, seconds = seconds})
	end
	local function flushScheduled()
		local current = table.clone(scheduled)
		table.clear(scheduled)
		for _, pending in ipairs(current) do
			if pending.at <= t.world:GetServerTimeNow() then pending.callback()
			else table.insert(scheduled, pending) end
		end
	end
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
	local function frame(marker)
		local value = {kind = "CFrame", marker = marker}
		function value:Inverse() return frame("inv(" .. marker .. ")") end
		return setmetatable(value, {__mul = function(a, b)
			return frame(tostring(a.marker) .. ">" .. tostring(b.marker))
		end})
	end
	local torso = mob:FindFirstChild("Torso")
	torso.CFrame = frame("torso")
	local hat = instance("Accessory", "Hat", mob)
	local handle = instance("Part", "Handle", hat)
	handle.CFrame = {fallen = true}
	local weld = instance("Weld", "AccessoryWeld", handle)
	weld.Part0, weld.Part1 = torso, handle
	weld.C0, weld.C1 = frame("c0"), frame("c1")
	local head = instance("Part", "Head", mob)
	head.CFrame = frame("head")
	local hair = instance("Accessory", "Hair", mob)
	local hairHandle = instance("Part", "Handle", hair)
	hairHandle.CFrame = {fallen = true}
	local hairAttachment = instance("Attachment", "HairAttachment", hairHandle)
	hairAttachment.CFrame = frame("hatt")
	local headAttachment = instance("Attachment", "HairAttachment", head)
	headAttachment.CFrame = frame("headatt")
	humanoid:SetAttribute("ManualRagdoll", true)
	humanoid:SetAttribute("RagdollRecoveryRequested", true)
	prompt.Triggered:Emit(owner)
	assert(not humanoid:GetAttribute("ManualRagdoll") and not humanoid:GetAttribute("RagdollRecoveryRequested"),
		"capture retained the previous ragdoll toggle or pending recovery")
	assert(model:GetAttribute("CapsuleOccupied") and root.Anchored, "NPC capture failed")
	assert(not torso.Anchored, "R6 anchored a limb so the body pose never replicated")
	assert(weld.Part0 == torso and weld.Part1 == handle and weld.Enabled and weld.C0.marker == "c0",
		"accessory weld was not seated on the captive")
	local hairWeld = hairHandle:FindFirstChild("AccessoryWeld")
	assert(hairWeld and hairWeld.Part0 == head and hairWeld.Part1 == hairHandle and hairWeld.Enabled,
		"attachment accessory was not welded to the captive")
	assert(root.CFrame.placement ~= nil, "capture did not use Platform")
	assert(humanoid.State == "Physics" and not humanoid.EvaluateStateMachine
		and humanoid.PlatformStand and not humanoid:GetStateEnabled("GettingUp"),
		"capsule played a get-up instead of holding still")
	assert(humanoid:GetAttribute("CapsuleLocked") and humanoid.WalkSpeed == 0 and tool.Parent == nil, "capture did not lock mob")
	t.ragdoll.Set(humanoid, true)
	assert(not humanoid:GetAttribute("Ragdolled"), "Late ragdoll entered the capsule and saved frozen recovery state")
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
	local unlockChecked = false
	humanoid:GetAttributeChangedSignal("CapsuleLocked"):Connect(function()
		if not humanoid:GetAttribute("CapsuleLocked") and humanoid.Health > 0 then
			assert(not root.Anchored and humanoid.EvaluateStateMachine and not humanoid.PlatformStand
				and mob:FindFirstChild("CapsuleRescueShield"), "Capsule unlocked before recovery and protection were ready")
			unlockChecked = true
		end
	end)
	prompt.Triggered:Emit(owner)
	assert(unlockChecked, "Rescue did not complete its protected unlock")
	assert(not model:GetAttribute("CapsuleOccupied") and not root.Anchored, "rescue left capsule occupied")
	assert(not mob:FindFirstChild("CapsuleHealth"), "rescue leaked health display")
	assert(not humanoid:GetAttribute("CapsuleLocked") and humanoid.WalkSpeed == 16 and tool.Parent == mob, "rescue failed to restore mob")
	assert(humanoid.EvaluateStateMachine and humanoid:GetStateEnabled("GettingUp")
		and not humanoid.PlatformStand and humanoid.State == "Running",
		"rescue left the captive in the capsule physics pose")
	t.runService.PreAnimation:Emit()
	assert(not animate.Disabled, "rescue did not restore animation controller")
	assert(humanoid.AutoRotate, "rescue left rotation locked by the capture ragdoll")
	assert(humanoid.BreakJointsOnDeath, "rescue did not restore normal death behavior")
	assert(mob:FindFirstChild("CapsuleRescueShield"), "Rescue did not grant a shield")
	prompt.Triggered:Emit(owner)
	assert(not model:GetAttribute("CapsuleOccupied"), "Rescue shield allowed immediate recapture")
	t.advance(0.9)
	flushScheduled()
	assert(mob:FindFirstChild("CapsuleRescueShield"), "Rescue shield expired before one second")
	t.advance(0.11)
	flushScheduled()
	assert(not mob:FindFirstChild("CapsuleRescueShield"), "Rescue shield failed to expire")
	assert(not root.Anchored and humanoid.EvaluateStateMachine and not humanoid.PlatformStand,
		"Delayed capsule settle refroze a rescued character")
	t.ragdoll.Set(humanoid, true)
	t.ragdoll.Set(humanoid, false, true)
	assert(humanoid.EvaluateStateMachine and not humanoid.PlatformStand,
		"A later ragdoll restored frozen capsule settings")
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
	assert(humanoid.State == "Dead" and humanoid.EvaluateStateMachine and not humanoid.BreakJointsOnDeath,
		"dead NPC never entered Dead, so a non-player rig does not respawn")
	assert(weld.Parent and weld.Part0 == torso and weld.Enabled, "accessory fell off when the captive died")
	assert(root.Anchored and not torso.Anchored and not prompt.Enabled, "dead captive anchored a limb or exposed rescue prompt")
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
	-- A pitched ragdoll root has to be stored upright. Identity joint transforms
	-- are local, so the captive otherwise looks straight while the server keeps the tilt.
	local pitched = instance("Model", "Capsule", t.world)
	local pitchedTrigger = instance("Part", "Trigger", pitched)
	pitchedTrigger.CFrame = trigger.CFrame
	local marker = instance("Part", "VictimPosition", pitched)
	marker.CFrame = setmetatable({
		kind = "CFrame", Position = Vector3.new(0, 5, 0),
		LookVector = Vector3.new(0, 0.6, -0.8), RightVector = Vector3.new(1, 0, 0),
	}, {})
	local pitchedMob, pitchedHumanoid, pitchedRoot = t.character("PitchedMob", Vector3.zero, false)
	pitchedHumanoid.MaxHealth = 100
	pitchedHumanoid:SetAttribute("GrappledBy", owner.UserId)
	t.runService.Heartbeat:Emit(1)
	local pitchedPrompt = assert(pitchedTrigger:FindFirstChild("CapsulePrompt"), "pitched capsule never registered")
	pitchedPrompt.Triggered:Emit(owner)
	assert(pitched.GetAttribute and pitched:GetAttribute("CapsuleOccupied") and pitchedRoot.Anchored, "pitched capture failed")
	assert(pitchedRoot.CFrame.LookVector and pitchedRoot.CFrame.LookVector.Y == 0, "capsule stored the ragdoll tilt")
	assert(pitchedHumanoid.State == "Physics" and not pitchedHumanoid:GetStateEnabled("GettingUp"), "pitched capture played a get-up")
	assert(pitchedRoot.Anchored and not pitchedMob:FindFirstChild("Torso").Anchored,
		"pitched R6 anchored a limb so the body stays where it was grappled")
	-- Health can reach 0 without Died while EvaluateStateMachine is off.
	pitchedHumanoid.Health = 0
	t.runService.Heartbeat:Emit(0.1)
	assert(pitchedHumanoid.State == "Dead" and pitchedHumanoid.EvaluateStateMachine
		and not pitchedHumanoid.BreakJointsOnDeath,
		"silent NPC death never entered Dead, so the rig does not respawn")
	-- Exercise real push/bomb queues across capture and same-frame rescue.
	;(function()
		local actorRoot = owner.Character:FindFirstChild("HumanoidRootPart")
		actorRoot.Position = Vector3.new(-4, 0, 0)
		actorRoot.CFrame = {LookVector = Vector3.new(1, 0, 0)}
		local push = instance("Tool", t.config.pushToolName, owner.Character)
		push:SetAttribute("PushTool", true)
		local target, targetHumanoid, targetRoot = t.character("CapsuleCombatTarget", Vector3.zero, false)
		targetHumanoid.MaxHealth = 100
		targetHumanoid.WalkSpeed, targetHumanoid.JumpPower, targetHumanoid.JumpHeight = 16, 50, 7
		targetHumanoid:SetAttribute("GrappledBy", owner.UserId)
		t.remotes.UsePush.OnServerEvent:Emit(owner)
		assert(targetHumanoid:GetAttribute("Ragdolled"), "Combat race test did not queue a real push")
		prompt.Triggered:Emit(owner)
		assert(targetRoot.Anchored and targetHumanoid:GetAttribute("CapsuleLocked"), "Push/capture overlap failed to capture")
		t.runService.PreSimulation:Emit(1 / 60)
		assert(targetRoot.AssemblyLinearVelocity.Magnitude == 0 and not targetHumanoid:GetAttribute("Ragdolled"),
			"Queued push modified a captive")
		t.advance(t.config.pushCooldown + 0.01)
		t.remotes.UsePush.OnServerEvent:Emit(owner)
		assert(not targetHumanoid:GetAttribute("BombRagdollUntil"), "New push stunned a capsule occupant")
		prompt.Triggered:Emit(owner)
		assert(targetHumanoid.EvaluateStateMachine and not targetHumanoid.PlatformStand, "Overlapping push left rescue immobilized")
		-- Start another knockdown, capture, and rescue before launch executes.
		t.advance(t.config.pushCooldown + 0.01)
		flushScheduled()
		t.remotes.UsePush.OnServerEvent:Emit(owner)
		assert(targetHumanoid:GetAttribute("Ragdolled"), "Second race did not queue a push")
		prompt.Triggered:Emit(owner)
		prompt.Triggered:Emit(owner)
		t.advance(1.01)
		flushScheduled()
		t.runService.PreSimulation:Emit(1 / 60)
		combatHeartbeat:Emit(1 / 60)
		assert(targetRoot.AssemblyLinearVelocity.Magnitude == 0 and not targetHumanoid:GetAttribute("BombRagdollUntil")
			and targetHumanoid.EvaluateStateMachine and not targetHumanoid.PlatformStand,
			"Pre-capture combat work ran after rescue and shield expiration")
		-- Shields must block actual bomb/push effects, not just display a bubble.
		targetHumanoid:SetAttribute("GrappledBy", nil)
		for _, name in ipairs({"SpawnShield", "EscapeShield", "CapsuleRescueShield"}) do
			local shield = instance("ForceField", name, target)
			t.advance(t.config.pushCooldown + 0.01)
			t.remotes.UsePush.OnServerEvent:Emit(owner)
			assert(not targetHumanoid:GetAttribute("BombRagdollUntil"), name .. " did not block push")
			local bomb = instance("Tool", t.config.bombToolName, owner.Character)
			bomb:SetAttribute("BombTool", true)
			t.remotes.ThrowBomb.OnServerEvent:Emit(owner, Vector3.new(20, 0, 0))
			t.advance(t.config.bombFuse + 0.01)
			combatHeartbeat:Emit(1 / 60)
			assert(not targetHumanoid:GetAttribute("BombRagdollUntil"), name .. " did not block bomb")
			bomb:Destroy()
			shield:Destroy()
		end
		local unshieldedBomb = instance("Tool", t.config.bombToolName, owner.Character)
		unshieldedBomb:SetAttribute("BombTool", true)
		t.advance(t.config.bombCooldown + 0.01)
		t.remotes.ThrowBomb.OnServerEvent:Emit(owner, Vector3.new(20, 0, 0))
		t.advance(t.config.bombFuse + 0.01)
		combatHeartbeat:Emit(1 / 60)
		assert(targetHumanoid:GetAttribute("BombRagdollUntil"), "Bomb protection test never hit an unshielded target")
		-- Capture after the blast queues its impulse, then rescue before the next
		-- Heartbeat. The old impulse must still be rejected after shield expiry.
		targetHumanoid:SetAttribute("GrappledBy", owner.UserId)
		prompt.Triggered:Emit(owner)
		prompt.Triggered:Emit(owner)
		t.advance(1.01)
		flushScheduled()
		combatHeartbeat:Emit(1 / 60)
		assert(targetRoot.AssemblyLinearVelocity.Magnitude == 0 and targetHumanoid.EvaluateStateMachine
			and not targetHumanoid:GetAttribute("Ragdolled"), "Queued bomb broke recovery after capsule rescue")
		unshieldedBomb:Destroy()
		assert(t.config.spawnShieldSeconds == 6 and t.config.escapeShieldSeconds == 6, "Requested shields are not six seconds")
		print("PASS: capsule combat overlap, protected rescue, stale launch cancellation, and shield durations")
	end)()
	t.env.task.delay = originalDelay
end

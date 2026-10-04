-- Runs the real game modules against a small Roblox API mock.
-- This validates state/cleanup, not the engine's physics solver or GUI rendering.
return function(sources)
	local objects, delayed = {}, {}
	local now = 10
	local function signal()
		local callbacks = {}
		local s = {}
		function s:Connect(callback)
			local connection = {active = true}
			function connection:Disconnect() self.active = false end
			table.insert(callbacks, {callback, connection})
			return connection
		end
		function s:Emit(...)
			for _, entry in ipairs(table.clone(callbacks)) do
				if entry[2].active then entry[1](...) end
			end
		end
		function s:Wait() return 0.05 end
		return s
	end
	local V = {}
	local vectorMT = {}
	function V.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, kind = "Vector3"}, vectorMT) end
	V.zero = V.new()
	vectorMT.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	vectorMT.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	vectorMT.__mul = function(a, b) return V.new(a.X * b, a.Y * b, a.Z * b) end
	vectorMT.__div = function(a, b) return V.new(a.X / b, a.Y / b, a.Z / b) end
	vectorMT.__index = function(a, key)
		if key == "Magnitude" then return math.sqrt(a.X^2 + a.Y^2 + a.Z^2) end
		if key == "Unit" then return a / a.Magnitude end
		if key == "Dot" then return function(_, b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end end
	end
	local identity = setmetatable({LookVector = V.new(0, 0, -1)}, {__mul = function(a) return a end})
	local function descendant(object, ancestor)
		local parent = object.Parent
		while parent do if parent == ancestor then return true end parent = parent.Parent end
		return false
	end
	local methods = {}
	local objectMT = {
		__index = function(object, key)
			if key == "WorldPosition" then return object.Parent.Position + (object.Position or V.new()) end
			return methods[key]
		end,
		__newindex = function(object, key, value)
			if key == "WorldPosition" then rawset(object, "Position", value - object.Parent.Position)
			else rawset(object, key, value) end
		end,
	}
	local function instance(class, name, parent)
		local object = setmetatable({
			ClassName = class, Name = name or class, Parent = parent, Enabled = true, attributes = {}, tags = {},
			Position = V.new(), Size = V.new(2, 2, 2), CFrame = identity, C0 = identity, C1 = identity, Transform = identity,
			Health = 100, HipHeight = 2, EvaluateStateMachine = true, AutoRotate = true, PlatformStand = false, CanCollide = false, Massless = false,
			AssemblyLinearVelocity = V.new(), AssemblyAngularVelocity = V.new(),
			CollisionGroup = "Default", CurrentPhysicalProperties = {Density = 1}, AssemblyMass = 5,
			Died = signal(), Destroying = signal(), Unequipped = signal(), CharacterRemoving = signal(), CharacterAdded = signal(),
			DescendantAdded = signal(), ChildAdded = signal(), OnServerEvent = signal(),
			Equipped = signal(), Activated = signal(),
		}, objectMT)
		table.insert(objects, object)
		return object
	end
	function methods:IsA(class)
		return self.ClassName == class or class == "BasePart" and self.ClassName == "Part"
	end
	function methods:GetChildren()
		local result = {}
		for _, object in ipairs(objects) do if object.Parent == self then table.insert(result, object) end end
		return result
	end
	function methods:GetDescendants()
		local result = {}
		for _, object in ipairs(objects) do if descendant(object, self) then table.insert(result, object) end end
		return result
	end
	function methods:FindFirstChild(name, recursive)
		for _, object in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do
			if object.Name == name then return object end
		end
	end
	function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
	function methods:FindFirstChildWhichIsA(class)
		for _, object in ipairs(self:GetChildren()) do if object:IsA(class) then return object end end
	end
	methods.FindFirstChildOfClass = methods.FindFirstChildWhichIsA
	function methods:GetPropertyChangedSignal(key) return self:GetAttributeChangedSignal("property:" .. key) end
	function methods:FindFirstAncestorOfClass(class)
		local parent = self.Parent
		while parent do if parent:IsA(class) then return parent end parent = parent.Parent end
	end
	function methods:SetAttribute(key, value)
		local previous = self.attributes[key]
		self.attributes[key] = value
		if previous ~= value and self.attributeSignals and self.attributeSignals[key] then
			self.attributeSignals[key]:Emit()
		end
	end
	function methods:GetAttributeChangedSignal(key)
		self.attributeSignals = self.attributeSignals or {}
		self.attributeSignals[key] = self.attributeSignals[key] or signal()
		return self.attributeSignals[key]
	end
	function methods:GetAttribute(key) return self.attributes[key] end
	function methods:HasTag(tag) return self.tags[tag] == true end
	function methods:AddTag(tag) self.tags[tag] = true end
	function methods:RemoveTag(tag) self.tags[tag] = nil end
	function methods:CanSetNetworkOwnership() return not self.Anchored end
	function methods:SetNetworkOwner(owner) self.NetworkOwner = owner end
	function methods:SetNetworkOwnershipAuto() self.NetworkOwner = "auto" end
	function methods:GetMass() return 5 end
	function methods:ChangeState(state) self.State = state end
	function methods:GetState() return self.State end
	function methods:GetStateEnabled(state) return not self.disabledStates or not self.disabledStates[state] end
	function methods:SetStateEnabled(state, enabled)
		self.disabledStates = self.disabledStates or {}
		self.disabledStates[state] = not enabled
	end
	function methods:ApplyAngularImpulse(impulse) self.lastAngularImpulse = impulse end
	function methods:UnequipTools()
		self.UnequippedCount = (self.UnequippedCount or 0) + 1
		for _, child in ipairs(self.Parent:GetChildren()) do
			if child:IsA("Tool") then
				child.Parent = nil
				child.Unequipped:Emit()
			end
		end
	end
	function methods:LoadCharacter() self.LoadCharacterCount = (self.LoadCharacterCount or 0) + 1 end
	function methods:Destroy()
		self.Destroying:Emit()
		for _, object in ipairs(self:GetChildren()) do object:Destroy() end
		self.Parent, self.destroyed = nil, true
	end
	function methods:FireClient(player, ...)
		self.messages = self.messages or {}
		table.insert(self.messages, {player = player, args = table.pack(...)})
	end
	function methods:FireServer(...)
		self.sent = self.sent or {}
		table.insert(self.sent, table.pack(...))
	end
	local players = instance("Players")
	players.PlayerAdded, players.PlayerRemoving = signal(), signal()
	local playerList = {}
	function players:GetPlayers() return playerList end
	function players:GetPlayerFromCharacter(character)
		for _, player in ipairs(playerList) do if player.Character == character then return player end end
	end
	local runService = {Heartbeat = signal(), PreSimulation = signal(), IsServer = function() return true end}
	function runService:BindToRenderStep(name, _, callback)
		self.renderBindings = self.renderBindings or {}
		self.renderBindings[name] = callback
	end
	local storage = instance("ReplicatedStorage")
	storage.Modules = instance("Folder", "Modules", storage)
	local configModule = instance("ModuleScript", "GrappleConfig", storage)
	local remoteModule = instance("ModuleScript", "GrappleRemotes", storage.Modules)
	local ragdollModule = instance("ModuleScript", "RagdollService", storage.Modules)
	local soundModule = instance("ModuleScript", "PlaySound", storage.Modules)
	local world = instance("Workspace")
	world.Gravity = 196.2
	local hitParts = {}
	function world:GetPartBoundsInBox() return hitParts end
	function world:Raycast() return nil end
	local services = {Players = players, RunService = runService, ReplicatedStorage = storage, Workspace = world, PhysicsService = {}}
	local env = setmetatable({
		game = {GetService = function(_, name) return assert(services[name], name) end},
		workspace = world, Vector3 = V, Instance = {new = instance},
		CFrame = {new = function() return identity end, lookAt = function() return identity end}, BrickColor = {new = function() return {} end},
		Color3 = {fromRGB = function() return {} end}, ColorSequence = {new = function() return {} end},
		PhysicalProperties = {new = function(d, f) return {Density = d, Friction = f} end},
		RaycastParams = {new = function() return {} end}, OverlapParams = {new = function() return {} end},
		Enum = {HumanoidStateType = {Physics = "Physics", Ragdoll = "Ragdoll", GettingUp = "GettingUp"},
			RenderPriority = {Camera = {Value = 200}},
			ForceLimitMode = {PerAxis = "PerAxis"}, ActuatorRelativeTo = {World = "World"},
			PositionAlignmentMode = {OneAttachment = "OneAttachment"}, RaycastFilterType = {Exclude = "Exclude"},
			Material = {Neon = "Neon"}, KeyCode = setmetatable({}, {__index = function(_, key) return key end})},
		os = {clock = function() return now end},
		task = {delay = function(_, fn) table.insert(delayed, fn) end, defer = function(fn, ...) fn(...) end, spawn = function(fn, ...) fn(...) end},
		typeof = function(value) return type(value) == "table" and value.kind or type(value) end,
	}, {__index = getfenv()})
	local function execute(source)
		local fn = assert(loadstring(source))
		setfenv(fn, env)
		return fn()
	end
	local config = execute(sources.config)
	local remotes = {}
	for _, name in ipairs({"FireGrapple", "ChangeLength", "ToggleWallMode", "ToggleRagdoll", "ResetCharacter", "GrappledPlayer", "GrappledWall", "HasBeenGrappled", "StruggleInput", "StruggleProgress"}) do
		remotes[name] = instance("RemoteEvent", name)
	end
	local ragdoll = execute(sources.ragdoll)
	env.require = function(module)
		if module == configModule then return config end
		if module == remoteModule then return remotes end
		if module == ragdollModule then return ragdoll end
		if module == soundModule then return function() end end
		error("Unexpected require")
	end
	local function character(name, position, r15)
		local model = instance("Model", name, world)
		local root = instance("Part", "HumanoidRootPart", model)
		root.Position = position
		local humanoid = instance("Humanoid", "Humanoid", model)
		local torso = instance("Part", r15 and "LowerTorso" or "Torso", model)
		local rootJoint = instance("Motor6D", r15 and "Root" or "RootJoint", root)
		rootJoint.Part0, rootJoint.Part1 = root, torso
		local count = r15 and 14 or 5
		for index = 1, count do
			local limb = instance("Part", "Limb" .. index, model)
			limb.Position = position
			local motor = instance("Motor6D", index == 1 and "Neck" or "Joint" .. index, torso)
			motor.Part0, motor.Part1 = torso, limb
		end
		return model, humanoid, root, rootJoint
	end
	local attacker = instance("Player", "Player1", players)
	attacker.UserId = -1
	local victim = instance("Player", "Player2", players)
	victim.UserId = -2
	attacker.Character = character("Player1", V.new(0, 0, 0), false)
	local victimCharacter, victimHumanoid, victimRoot, rootMotor = character("Player2", V.new(0, 0, 20), true)
	victim.Character = victimCharacter
	playerList = {attacker, victim}
	local gun = instance("Tool", config.toolName, attacker.Character)
	local handle = instance("Part", "Handle", gun)
	handle.Anchored, handle.CanCollide = true, true
	local firePoint = instance("Attachment", "FirePoint", handle)
	local function fire()
		now += 0.2
		remotes.FireGrapple.OnServerEvent:Emit(attacker, V.new(0, 0, 20), V.new(0, 0, 0))
	end
	execute(sources.server)
	hitParts = {victimRoot}
	-- An overlap hit must not allow a player to shoot through a solid wall.
	local wall = instance("Part", "Wall", world)
	world.Raycast = function() return {Instance = wall, Position = V.new(0, 0, 5)} end
	fire()
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "grapple went through wall")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	world.Raycast = function() return nil end
	fire()
	assert(victimHumanoid:GetAttribute("GrappledBy") == attacker.UserId, "grapple not established")
	assert(victimHumanoid:GetAttribute("Ragdolled") == true, "victim not ragdolled")
	assert(rootMotor.Enabled, "root must remain attached to torso")
	assert(not victimRoot.CanCollide, "invisible root must not drag against floor")
	local jointFolder = assert(victimCharacter:FindFirstChild("GrappleRagdollJoints"))
	assert(#jointFolder:GetChildren() == 14, "all R15 limb joints must be constrained")
	for _, object in ipairs(victimCharacter:GetDescendants()) do
		if object:IsA("Motor6D") and object ~= rootMotor then assert(not object.Enabled, "stiff limb motor") end
		if object:IsA("BasePart") then assert(object.NetworkOwner == attacker, "split ragdoll ownership") end
	end
	assert(not handle.Anchored and not handle.CanCollide and handle.Massless, "gun physics not normalized")
	assert(victimHumanoid.State == "Ragdoll" and not victimHumanoid:GetStateEnabled("GettingUp"), "victim is not held in ragdoll state")
	local rope = assert(victimRoot:FindFirstChildWhichIsA("RopeConstraint"))
	assert(rope.Enabled and rope.WinchEnabled, "player rope is not physically active")
	assert(rope:GetAttribute("PlayerGrapple") == true, "player rope is not identified")
	assert(rope.WinchForce == config.playerWinchForce, "player rope does not use lifting force")
	assert(rope.Attachment0.Parent == attacker.Character:FindFirstChild("HumanoidRootPart"), "rope still attached to gun limb")
	assert(rope.Attachment1.Parent == victimRoot, "rope is not attached to victim center")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, -1e6)
	assert(rope.WinchTarget >= 16, "rope length teleport accepted")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, 0/0)
	assert(rope.WinchTarget == rope.WinchTarget, "NaN length accepted")
	now += 0.5
	runService.Heartbeat:Emit(0.1)
	assert(rope.WinchTarget < rope.Length, "shortening did not reel the physical rope")
	local progressBefore = #(remotes.StruggleProgress.messages or {})
	remotes.StruggleInput.OnServerEvent:Emit(attacker)
	assert(#(remotes.StruggleProgress.messages or {}) == progressBefore, "attacker escaped for victim")
	victimRoot.CFrame = {LookVector = V.new(1, 0.8, 0)}
	victimRoot.AssemblyAngularVelocity = V.new(4, 3, 2)
	for _ = 1, config.maxStruggleValue + 10 do
		now += 0.08
		remotes.StruggleInput.OnServerEvent:Emit(victim)
	end
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "escape failed")
	assert(victimHumanoid:GetAttribute("Ragdolled") == false, "escape failed to recover")
	assert(rope.destroyed, "escape leaked physical rope")
	assert(victimRoot.NetworkOwner == nil, "recovery pose was not server-owned")
	assert(victimRoot.CFrame == identity and victimRoot.AssemblyAngularVelocity.Magnitude == 0, "server did not straighten released victim")
	assert(victimRoot.CanCollide == false and victimHumanoid.AutoRotate, "recovery did not restore properties")
	local messages = remotes.HasBeenGrappled.messages
	assert(messages[#messages].args.n == 0, "victim never received end event")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(victimRoot.NetworkOwner == victim, "victim ownership not restored after stabilization")
	-- Manual ragdolls must survive grapple release.
	victimHumanoid:AddTag("Ragdoll")
	ragdoll.Set(victimHumanoid, true)
	fire()
	fire()
	assert(victimHumanoid:GetAttribute("Ragdolled"), "release removed voluntary ragdoll")
	ragdoll.Set(victimHumanoid, false)
	victimHumanoid:RemoveTag("Ragdoll")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	-- Leaving as a victim tears down the attacker's state and restores gun cooldown.
	fire()
	players.PlayerRemoving:Emit(victim)
	assert(not gun:GetAttribute("HasGrappled") and not gun:GetAttribute("InCooldown"), "leave stuck grapple/cooldown")
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "leave left grapple marker")
	-- A connected grapple must survive indefinitely; no automatic expiry.
	fire()
	now += 3600
	runService.Heartbeat:Emit(0.1)
	assert(victimHumanoid:GetAttribute("GrappledBy") == attacker.UserId, "grapple expired automatically")
	fire()
	-- R6 joints must disable and restore as well.
	local r6, hum6, root6, motor6 = character("R6", V.new(), false)
	ragdoll.Set(hum6, true)
	assert(#r6:FindFirstChild("GrappleRagdollJoints"):GetChildren() == 5 and motor6.Enabled and not root6.CanCollide)
	ragdoll.Set(hum6, false)
	assert(config.ragdollToggle_Cooldown == 0.5, "ragdoll recovery cooldown should be half a second")
	assert(hum6:GetAttribute("RagdollRecoveredAt") == now, "cooldown did not start on recovery")
	for _, object in ipairs(r6:GetDescendants()) do if object:IsA("Motor6D") then assert(object.Enabled) end end
	-- Upgraded player avatars use AnimationConstraint, not Motor6D.
	local upgradedRig = instance("Model", "UpgradedR15", world)
	local upgradedHumanoid = instance("Humanoid", "Humanoid", upgradedRig)
	local upgradedTorso = instance("Part", "UpperTorso", upgradedRig)
	local upgradedArm = instance("Part", "LeftUpperArm", upgradedRig)
	local shoulder0 = instance("Attachment", "Shoulder", upgradedTorso)
	local shoulder1 = instance("Attachment", "Shoulder", upgradedArm)
	local animatedJoint = instance("AnimationConstraint", "LeftShoulder", upgradedTorso)
	animatedJoint.Attachment0, animatedJoint.Attachment1 = shoulder0, shoulder1
	local nativeSocket = instance("BallSocketConstraint", "LeftShoulderSocket", upgradedTorso)
	nativeSocket.Attachment0, nativeSocket.Attachment1 = shoulder0, shoulder1
	ragdoll.Set(upgradedHumanoid, true)
	assert(not animatedJoint.Enabled and nativeSocket.Enabled, "upgraded avatar remained animated/stiff")
	assert(#upgradedRig:FindFirstChild("GrappleRagdollJoints"):GetChildren() == 0, "native avatar sockets duplicated")
	ragdoll.Set(upgradedHumanoid, false)
	assert(animatedJoint.Enabled and nativeSocket.Enabled, "native rig recovery changed socket defaults")
	-- Swap Player1/Player2 roles: the same ownership and recovery rules must apply.
	local reverseGun = instance("Tool", config.toolName, victimCharacter)
	local reverseHandle = instance("Part", "Handle", reverseGun)
	reverseHandle.Position = victimRoot.Position
	instance("Attachment", "FirePoint", reverseHandle)
	local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
	hitParts = {attackerRoot}
	now += 0.1
	remotes.FireGrapple.OnServerEvent:Emit(victim, attackerRoot.Position, victimRoot.Position)
	local attackerHumanoid = attacker.Character:FindFirstChildWhichIsA("Humanoid")
	assert(attackerHumanoid:GetAttribute("GrappledBy") == victim.UserId and attackerRoot.NetworkOwner == victim, "reverse grapple is asymmetric")
	attacker.CharacterRemoving:Emit()
	assert(attackerRoot.NetworkOwner == nil and not reverseGun:GetAttribute("HasGrappled"), "reverse recovery was not stabilized by server")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attackerRoot.NetworkOwner == attacker, "reverse recovery ownership was not restored")
	-- Duplicate X paths must not toggle twice, and a stale GUI cooldown cannot jam firing.
	gun.Parent = attacker.Character
	now += 0.2
	remotes.ToggleWallMode.OnServerEvent:Emit(attacker)
	remotes.ToggleWallMode.OnServerEvent:Emit(attacker)
	assert(gun:GetAttribute("WallMode") == true, "duplicate X handlers cancelled target mode")
	now += 0.2
	remotes.ToggleWallMode.OnServerEvent:Emit(attacker)
	gun:SetAttribute("InCooldown", true)
	hitParts = {victimRoot}
	now += 0.2
	remotes.FireGrapple.OnServerEvent:Emit(attacker, victimRoot.Position, V.new(0, 0, -100))
	assert(victimHumanoid:GetAttribute("GrappledBy") == attacker.UserId, "zoomed camera or stale UI cooldown jammed firing")
	fire()
	-- Death must remove the physical rope but leave the dead character ragdolled.
	hitParts = {victimRoot}
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	fire()
	local deathRope = assert(victimRoot:FindFirstChildWhichIsA("RopeConstraint"))
	victimHumanoid.Health = 0
	victimHumanoid.Died:Emit()
	assert(deathRope.destroyed and victimHumanoid:GetAttribute("Ragdolled"), "death cleanup resurrected or retained rope")
	-- The attacker's client must also suppress the remote victim's state machine.
	runService.IsServer = function() return false end
	local clientRagdoll = execute(sources.ragdoll)
	clientRagdoll.InitClient()
	assert(not victimHumanoid.EvaluateStateMachine, "remote victim retained humanoid forces")
	assert(attackerHumanoid.EvaluateStateMachine, "healthy character state machine was disabled")
	victimRoot.AssemblyAngularVelocity = V.new(3, 2, 1)
	runService.PreSimulation:Emit()
	assert(victimRoot.AssemblyAngularVelocity.Magnitude == 0, "ragdoll camera root retained angular jitter")
	hum6:SetAttribute("Ragdolled", true)
	assert(not hum6.EvaluateStateMachine and hum6.PlatformStand, "client missed newly activated ragdoll")
	hum6:SetAttribute("Ragdolled", false)
	assert(hum6.EvaluateStateMachine and not hum6.PlatformStand, "client did not restore state machine")
	local _, lateHumanoid = character("LateSpawn", V.new(), false)
	world.DescendantAdded:Emit(lateHumanoid)
	lateHumanoid:SetAttribute("Ragdolled", true)
	assert(not lateHumanoid.EvaluateStateMachine, "client missed late spawn")
	ragdoll.Set(upgradedHumanoid, true)
	animatedJoint.Enabled = true
	runService.PreSimulation:Emit()
	assert(not animatedJoint.Enabled, "client did not enforce upgraded ragdoll joint")
	-- Firing is independent of movement and legacy Tool.Enabled, with click deduplication.
	local input = {InputBegan = signal(), GetFocusedTextBox = function() return nil end,
		GetMouseLocation = function() return {X = 100, Y = 100} end}
	services.UserInputService = input
	players.LocalPlayer = attacker
	function attacker:GetMouse() return {} end
	local aimPixels
	world.CurrentCamera = {
		CFrame = {Position = V.new(0, 0, -100)}, ViewportSize = {X = 800, Y = 600},
		ScreenPointToRay = function() error("Raw mouse coordinates must not apply a GUI inset") end,
		ViewportPointToRay = function(_, x, y)
			aimPixels = {x, y}
			return {Origin = V.new(), Direction = V.new(0, 0, 1)}
		end,
	}
	local clickedPoint = V.new(7, 3, 100)
	world.Raycast = function(_, _, _, params)
		assert(params.FilterDescendantsInstances[1] == attacker.Character, "aim ray must exclude own character")
		return {Position = clickedPoint}
	end
	env.Enum.UserInputType = {MouseButton1 = "MouseButton1", Keyboard = "Keyboard"}
	local toolClient = execute(sources.tool)
	toolClient.Init(gun)
	gun.Enabled = false
	now += 0.2
	input.InputBegan:Emit({UserInputType = "MouseButton1"}, false)
	gun.Activated:Emit()
	assert(#remotes.FireGrapple.sent == 1, "mouse fallback duplicated or missed shot")
	assert(aimPixels[1] == 100 and aimPixels[2] == 100, "mouse pixel changed during ray conversion")
	assert(remotes.FireGrapple.sent[1][1] == clickedPoint, "shot target differs from exact aim ray hit")
	input.InputBegan:Emit({UserInputType = "Keyboard", KeyCode = "W"}, false)
	assert(#remotes.FireGrapple.sent == 1, "movement fired the gun")
	now += 0.2
	toolClient.Fire(gun, true)
	assert(#remotes.FireGrapple.sent == 2, "touch fire did not use shared firing path")
	assert(aimPixels[1] == 400 and aimPixels[2] == 300, "touch center aim changed")
	local unequipsBefore = attackerHumanoid.UnequippedCount or 0
	input.InputBegan:Emit({UserInputType = "Keyboard", KeyCode = "One"}, true)
	assert(gun.Parent == attacker.Character and (attackerHumanoid.UnequippedCount or 0) == unequipsBefore, "grapple code hijacked the normal hotbar key")
	-- Exercise the actual toggle handler: both entering and leaving ragdoll have
	-- the same 0.5-second cooldown.
	services.CollectionService = {
		GetInstanceAddedSignal = function() return signal() end,
		GetInstanceRemovedSignal = function() return signal() end,
	}
	services.StarterGui = instance("Folder", "StarterGui")
	services.PhysicsService.RegisterCollisionGroup = function() end
	services.PhysicsService.CollisionGroupSetCollidable = function() end
	execute(sources.lifecycle)
	now += 1
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:HasTag("Ragdoll"), "ready player could not ragdoll")
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:HasTag("Ragdoll"), "ragdoll could be cancelled without its cooldown")
	now += 0.49
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:HasTag("Ragdoll"), "ragdoll cancellation cooldown ended early")
	now += 0.01
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(not attackerHumanoid:HasTag("Ragdoll"), "ragdoll could not recover after its cooldown")
	local recoveredAt = now
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(not attackerHumanoid:HasTag("Ragdoll"), "immediate re-ragdoll bypassed cooldown")
	now = recoveredAt + 0.49
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(not attackerHumanoid:HasTag("Ragdoll"), "re-ragdoll cooldown ended early")
	now = recoveredAt + 0.5
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:HasTag("Ragdoll"), "cooldown did not expire after half a second")
	-- A dead ragdoll's camera follows HumanoidRootPart, so that root must not
	-- pass through the floor even when it was already ragdolled before death.
	remotes.ResetCharacter.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid.Health == 0, "reset request did not kill a ragdolled player")
	attackerHumanoid.Died:Emit()
	assert(attackerRoot.CanCollide, "dead ragdoll root can fall through the floor")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attacker.LoadCharacterCount == 1, "dead player did not receive respawn fallback")
	attackerHumanoid.Health = 100
	world.FallenPartsDestroyHeight = -100
	attackerRoot.Position = V.new(0, -75, 0)
	runService.Heartbeat:Emit(0.1)
	assert(attackerHumanoid.Health == 0, "falling ragdoll was not killed before the void")
	print("PASS: gameplay regressions, physical body rope, server recovery pose, normal hotbar input, exact aim, ragdoll cooldown")
end

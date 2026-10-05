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
			if key == "AssemblyRootPart" then return object end
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
			AssemblyLinearVelocity = V.new(), AssemblyAngularVelocity = V.new(), RootPriority = 0, MaxFrictionTorque = 0,
			CollisionGroup = "Default", CurrentPhysicalProperties = {Density = 1}, AssemblyMass = 5,
			Died = signal(), Destroying = signal(), Unequipped = signal(), CharacterRemoving = signal(), CharacterAdded = signal(),
			DescendantAdded = signal(), ChildAdded = signal(), OnServerEvent = signal(), OnClientEvent = signal(),
			Equipped = signal(), Activated = signal(), Touched = signal(),
		}, objectMT)
		table.insert(objects, object)
		return object
	end
	function methods:IsA(class)
		return self.ClassName == class or class == "BasePart" and self.ClassName == "Part"
	end
	function methods:IsDescendantOf(ancestor) return descendant(self, ancestor) end
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
	function methods:SetNetworkOwner(owner)
		self.NetworkOwner, self.OwnershipAuto = owner, false
		self.OwnershipWrites = (self.OwnershipWrites or 0) + 1
	end
	function methods:GetNetworkOwner() return self.NetworkOwner end
	function methods:GetNetworkOwnershipAuto() return self.OwnershipAuto ~= false end
	function methods:ApplyImpulse(impulse) self.AssemblyLinearVelocity += impulse / self.AssemblyMass end
	function methods:SetNetworkOwnershipAuto() self.NetworkOwner, self.OwnershipAuto = "auto", true end
	function methods:GetMass() return 5 end
	function methods:ChangeState(state) self.State = state end
	function methods:Move(direction) self.MoveDirection = direction end
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
	function methods:LoadCharacterAsync()
		self.LoadAttempts = (self.LoadAttempts or 0) + 1
		if self.FailLoad then error("simulated character load failure") end
		self:LoadCharacter()
	end
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
	function players:GetPlayerByUserId(id)
		for _, player in ipairs(playerList) do if player.UserId == id then return player end end
	end
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
		warn = function() end,
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
	for _, name in ipairs({"FireGrapple", "ChangeLength", "ToggleWallMode", "ToggleRagdoll", "ResetCharacter", "GrappledPlayer", "GrappledWall", "HasBeenGrappled", "GrappleVictimState", "StruggleInput", "StruggleProgress"}) do
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
		now += 0.4
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
	assert(not rootMotor.Enabled, "animated root must be disabled during ragdoll")
	assert(not victimRoot.CanCollide, "invisible root must not drag against floor")
	local jointFolder = assert(victimCharacter:FindFirstChild("GrappleRagdollJoints"))
	assert(#jointFolder:GetChildren() == 15, "R15 needs 14 limb sockets and one rigid root weld")
	local rootWeld = assert(jointFolder:FindFirstChild("RagdollRootWeld"))
	assert(rootWeld.Enabled and rootWeld.Part0 == victimRoot and rootWeld.Part1 == rootMotor.Part1, "root lost rigid torso connection")
	for _, object in ipairs(victimCharacter:GetDescendants()) do
		if object:IsA("Motor6D") and object ~= rootMotor then assert(not object.Enabled, "stiff limb motor") end
		if object:IsA("BasePart") then assert(object.NetworkOwner == attacker, "split ragdoll ownership") end
	end
	assert(not handle.Anchored and not handle.CanCollide and handle.Massless, "gun physics not normalized")
	assert(victimHumanoid.State == "Physics" and not victimHumanoid:GetStateEnabled("GettingUp"), "victim is not held in passive physics state")
	local rope = assert(victimRoot:FindFirstChildWhichIsA("RopeConstraint"))
	assert(rope.Enabled and not rope.WinchEnabled, "player rope must use a fixed length, not a winch")
	assert(rope:GetAttribute("PlayerGrapple") == true, "player rope is not identified")
	assert(rope.Attachment0.Parent == attacker.Character:FindFirstChild("HumanoidRootPart"), "rope still attached to gun limb")
	assert(rope.Attachment1.Parent == victimRoot, "rope is not attached to victim center")
	now += 0.1
	remotes.FireGrapple.OnServerEvent:Emit(attacker, victimRoot.Position, V.zero)
	assert(not rope.destroyed, "accidental second click released a newly caught player")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, 12)
	assert(rope.Length == 12, "reel-in did not immediately set the actual rope length")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, 0/0)
	assert(rope.Length == 12, "NaN length changed the fixed rope")
	now += 0.5
	runService.Heartbeat:Emit(0.1)
	assert(rope.Length == 12, "rope length changed after input stopped")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, 25)
	assert(rope.Length == 25, "reel-out did not permanently increase length")
	local progressBefore = #(remotes.StruggleProgress.messages or {})
	remotes.StruggleInput.OnServerEvent:Emit(attacker)
	assert(#(remotes.StruggleProgress.messages or {}) == progressBefore, "attacker escaped for victim")
	victimRoot.CFrame = {LookVector = V.new(1, 0.8, 0)}
	victimRoot.AssemblyAngularVelocity = V.new(4, 3, 2)
	victimRoot.AssemblyLinearVelocity = V.new(10, 25, -3)
	local releasePose = victimRoot.CFrame
	for _ = 1, config.maxStruggleValue + 10 do
		now += 0.08
		remotes.StruggleInput.OnServerEvent:Emit(victim)
	end
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "escape failed")
	assert(victimHumanoid:GetAttribute("Ragdolled") == true and victimHumanoid:GetAttribute("GrapplePhysicsLocked"), "escape resumed simulation before ownership returned")
	assert(rope.destroyed, "escape leaked physical rope")
	assert(victimRoot.NetworkOwner == attacker, "release changed simulator before settling")
	assert(victimRoot.CFrame == releasePose and victimRoot.AssemblyLinearVelocity.Y == 25, "release teleported or erased airborne momentum")
	local messages = remotes.HasBeenGrappled.messages
	assert(messages[#messages].args.n == 0, "victim never received end event")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(victimRoot.NetworkOwner == victim, "victim ownership not restored after stabilization")
	assert(victimHumanoid:GetAttribute("Ragdolled") == false and not victimHumanoid:GetAttribute("GrapplePhysicsLocked"), "escape failed to recover after handoff")
	assert(victimRoot.CanCollide == false and victimHumanoid.AutoRotate, "recovery did not restore properties")
	assert(rootMotor.Enabled and not rootWeld.Enabled and victimRoot.RootPriority == 0, "recovery failed to restore animated root/priority")
	assert(victimRoot.CFrame == releasePose and victimRoot.AssemblyLinearVelocity.Y == 25, "handoff rewrote the released pose or momentum")
	-- An earlier release timer must not steal a recaptured victim or preserve
	-- a grapple-created ragdoll as though it were voluntary.
	fire()
	fire()
	local staleRelease = table.clone(delayed)
	table.clear(delayed)
	fire()
	local currentSession = victimHumanoid:GetAttribute("GrapplePhysicsSession")
	for _, fn in ipairs(staleRelease) do fn() end
	assert(victimRoot.NetworkOwner == attacker and victimHumanoid:GetAttribute("GrapplePhysicsLocked"), "stale release stole recaptured victim")
	assert(victimHumanoid:GetAttribute("GrapplePhysicsSession") == currentSession, "stale release cleared new session")
	fire()
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(not victimHumanoid:GetAttribute("Ragdolled"), "recapture lost automatic ragdoll recovery")
	-- Ownership rejection must release the rope and eventually unlock the victim.
	victimRoot.Anchored = true
	fire()
	assert(not victimRoot:FindFirstChildWhichIsA("RopeConstraint"), "unassignable victim retained tether")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(not victimHumanoid:GetAttribute("GrapplePhysicsLocked"), "ownership failure left victim locked")
	victimRoot.Anchored = false
	-- Manual ragdolls must survive grapple release.
	victimHumanoid:AddTag("Ragdoll")
	ragdoll.Set(victimHumanoid, true)
	local looseLimb = victimCharacter:FindFirstChild("Limb1")
	assert(looseLimb.NetworkOwner == victim and not looseLimb:GetNetworkOwnershipAuto(), "voluntary ragdoll left limbs on automatic ownership")
	looseLimb.NetworkOwner, looseLimb.OwnershipAuto = attacker, true
	runService.Heartbeat:Emit(0.016)
	assert(looseLimb.NetworkOwner == victim and not looseLimb:GetNetworkOwnershipAuto(), "voluntary ragdoll ownership drift was not repaired")
	fire()
	fire()
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(victimHumanoid:GetAttribute("Ragdolled"), "release removed voluntary ragdoll")
	ragdoll.Set(victimHumanoid, false)
	victimHumanoid:RemoveTag("Ragdoll")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	fire()
	victimHumanoid:SetAttribute("BombRagdollUntil", now + 5)
	fire()
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(victimRoot.NetworkOwner == victim and victimHumanoid:GetAttribute("Ragdolled"), "grapple release bypassed bomb stun or retained ownership")
	assert(not victimHumanoid:GetAttribute("GrapplePhysicsLocked"), "bomb stun retained grapple lock")
	victimHumanoid:SetAttribute("BombRagdollUntil", nil)
	ragdoll.Set(victimHumanoid, false)
	victimHumanoid:RemoveTag("Ragdoll")
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
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	-- R6 joints must disable and restore as well.
	local r6, hum6, root6, motor6 = character("R6", V.new(), false)
	root6.Massless, root6.RootPriority = true, -10
	ragdoll.Set(hum6, true)
	assert(#r6:FindFirstChild("GrappleRagdollJoints"):GetChildren() == 6 and not motor6.Enabled and not root6.CanCollide)
	assert(not root6.Massless and root6.RootPriority == 127 and not root6:GetNetworkOwnershipAuto(), "NPC root was not stable/server-owned")
	assert(r6:FindFirstChild("GrappleRagdollJoints"):FindFirstChild("Neck").MaxFrictionTorque > 0, "ragdoll joints have no settling friction")
	ragdoll.Set(hum6, false)
	assert(root6.Massless and root6.RootPriority == -10, "ragdoll recovery lost original mass/root settings")
	assert(config.ragdollToggle_Cooldown == 0.5, "ragdoll recovery cooldown should be half a second")
	assert(hum6:GetAttribute("RagdollRecoveredAt") == now, "cooldown did not start on recovery")
	for _, object in ipairs(r6:GetDescendants()) do if object:IsA("Motor6D") then assert(object.Enabled) end end
	-- Upgraded player avatars use AnimationConstraint, not Motor6D.
	local upgradedRig = instance("Model", "UpgradedR15", world)
	local upgradedHumanoid = instance("Humanoid", "Humanoid", upgradedRig)
	local upgradedTorso = instance("Part", "UpperTorso", upgradedRig)
	local upgradedRoot = instance("Part", "HumanoidRootPart", upgradedRig)
	local root0 = instance("Attachment", "Root", upgradedRoot)
	local root1 = instance("Attachment", "Root", upgradedTorso)
	local animatedRoot = instance("AnimationConstraint", "RootJoint", upgradedTorso)
	animatedRoot.Attachment0, animatedRoot.Attachment1 = root0, root1
	local upgradedArm = instance("Part", "LeftUpperArm", upgradedRig)
	local shoulder0 = instance("Attachment", "Shoulder", upgradedTorso)
	local shoulder1 = instance("Attachment", "Shoulder", upgradedArm)
	local animatedJoint = instance("AnimationConstraint", "LeftShoulder", upgradedTorso)
	animatedJoint.Attachment0, animatedJoint.Attachment1 = shoulder0, shoulder1
	local nativeSocket = instance("BallSocketConstraint", "LeftShoulderSocket", upgradedTorso)
	nativeSocket.Attachment0, nativeSocket.Attachment1 = shoulder0, shoulder1
	nativeSocket.MaxFrictionTorque = 2
	ragdoll.Set(upgradedHumanoid, true)
	assert(not animatedJoint.Enabled and nativeSocket.Enabled, "upgraded avatar remained animated/stiff")
	local upgradedFolder = upgradedRig:FindFirstChild("GrappleRagdollJoints")
	assert(#upgradedFolder:GetChildren() == 1, "native avatar sockets duplicated")
	assert(not animatedRoot.Enabled and upgradedFolder:FindFirstChild("RagdollRootWeld").Enabled, "upgraded root remained animated")
	assert(nativeSocket.MaxFrictionTorque == 5, "native socket lacked settling friction")
	ragdoll.Set(upgradedHumanoid, false)
	assert(animatedJoint.Enabled and nativeSocket.Enabled, "native rig recovery changed socket defaults")
	assert(animatedRoot.Enabled and not upgradedFolder:FindFirstChild("RagdollRootWeld").Enabled and nativeSocket.MaxFrictionTorque == 2, "upgraded root/friction failed to restore")
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
	attacker.CharacterRemoving:Emit(attacker.Character)
	assert(attackerRoot.NetworkOwner == "auto" and not reverseGun:GetAttribute("HasGrappled"), "removed character retained grapple ownership")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attackerRoot.NetworkOwner == "auto", "stale handoff reclaimed removed character")
	-- Four-player role matrix, including Player3 -> Player1 and Player4 -> Player2.
	-- Model a limb split being discovered only AFTER the initial ownership call.
	local third = instance("Player", "Player3", players)
	third.UserId = -3
	third.Character = character("Player3", V.new(0, 0, 40), true)
	local fourth = instance("Player", "Player4", players)
	fourth.UserId = -4
	fourth.Character = character("Player4", V.new(0, 0, 60), false)
	playerList = {attacker, victim, third, fourth}
	players.PlayerAdded:Emit(third)
	players.PlayerAdded:Emit(fourth)
	for _, shooter in ipairs(playerList) do
		for _, target in ipairs(playerList) do
			if shooter == target then continue end
			local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
			local shooterRoot = shooter.Character:FindFirstChild("HumanoidRootPart")
			local testGun = instance("Tool", config.toolName, shooter.Character)
			local testHandle = instance("Part", "Handle", testGun)
			testHandle.Position = shooterRoot.Position
			instance("Attachment", "FirePoint", testHandle)
			for _, part in ipairs(target.Character:GetChildren()) do
				if part:IsA("BasePart") then
					part.AssemblyRootPart = targetRoot
					part.NetworkOwner, part.OwnershipAuto = attacker, true
				end
			end
			hitParts = {targetRoot}
			now += 0.4
			remotes.FireGrapple.OnServerEvent:Emit(shooter, targetRoot.Position, shooterRoot.Position)
			assert(targetHumanoid:GetAttribute("GrappledBy") == shooter.UserId, "role matrix missed capture")
			for _, part in ipairs(target.Character:GetChildren()) do
				if part:IsA("BasePart") then part.AssemblyRootPart = nil end
			end
			runService.Heartbeat:Emit(0.016)
			for _, part in ipairs(target.Character:GetChildren()) do
				if part:IsA("BasePart") then
					assert(part.NetworkOwner == shooter and not part:GetNetworkOwnershipAuto(), "split limb picked Player1 instead of grappler")
				end
			end
			local limb = target.Character:FindFirstChild("Limb1")
			limb.NetworkOwner, limb.OwnershipAuto = target, true
			now += 0.3
			runService.Heartbeat:Emit(0.3)
			assert(limb.NetworkOwner == shooter and not limb:GetNetworkOwnershipAuto(), "ownership audit missed drift")
			local writes = limb.OwnershipWrites
			now += 0.3
			runService.Heartbeat:Emit(0.3)
			assert(limb.OwnershipWrites == writes, "stable ownership was unnecessarily rewritten")
			remotes.FireGrapple.OnServerEvent:Emit(shooter, targetRoot.Position, shooterRoot.Position)
			for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
			assert(targetRoot.NetworkOwner == target and not targetHumanoid:GetAttribute("Ragdolled"), "role matrix release failed")
			testGun:Destroy()
		end
	end
	players.PlayerRemoving:Emit(third)
	players.PlayerRemoving:Emit(fourth)
	playerList = {attacker, victim}
	-- Duplicate X paths must not toggle twice, and a stale GUI cooldown cannot jam firing.
	gun.Parent = attacker.Character
	now += 0.2
	remotes.ToggleWallMode.OnServerEvent:Emit(attacker)
	remotes.ToggleWallMode.OnServerEvent:Emit(attacker)
	assert(gun:GetAttribute("WallMode") == true, "duplicate X handlers cancelled target mode")
	world.Raycast = function() return {Instance = wall, Position = V.new(0, 0, 100)} end
	now += 0.2
	remotes.FireGrapple.OnServerEvent:Emit(attacker, V.new(0, 0, 100), V.new(0, 0, -100))
	local wallRope = assert(wall:FindFirstChildWhichIsA("RopeConstraint"))
	attackerRoot.AssemblyLinearVelocity = V.new(12, 0, 0)
	remotes.ChangeLength.OnServerEvent:Emit(attacker, -1e6)
	assert(wallRope.Length == config.minRopeLength and not wallRope.WinchEnabled, "wall reel did not immediately set fixed length")
	runService.Heartbeat:Emit(0.1)
	assert(attackerRoot.AssemblyLinearVelocity.X == 12, "old wall velocity pull is still running")
	now += 20
	runService.Heartbeat:Emit(0.1)
	assert(not wallRope.destroyed, "wall grapple expired automatically")
	remotes.ChangeLength.OnServerEvent:Emit(attacker, 80)
	assert(wallRope.Length == 80, "wall reel-out did not stick")
	remotes.FireGrapple.OnServerEvent:Emit(attacker, V.new(0, 0, 100), V.new(0, 0, -100))
	assert(wallRope.destroyed and not wall:FindFirstChildWhichIsA("RopeConstraint"), "wall click should release, not refire")
	world.Raycast = function() return nil end
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
	assert(victimRoot.AssemblyAngularVelocity.Magnitude > 0, "observer rewrote the physics owner's velocity")
	hum6:SetAttribute("Ragdolled", true)
	assert(not hum6.EvaluateStateMachine and hum6.PlatformStand, "client missed newly activated ragdoll")
	hum6:SetAttribute("Ragdolled", false)
	assert(hum6.EvaluateStateMachine and not hum6.PlatformStand, "client did not restore state machine")
	local _, lateHumanoid = character("LateSpawn", V.new(), false)
	world.DescendantAdded:Emit(lateHumanoid)
	lateHumanoid:SetAttribute("Ragdolled", true)
	assert(not lateHumanoid.EvaluateStateMachine, "client missed late spawn")
	local _, streamedHumanoid = character("StreamedRagdoll", V.zero, false)
	streamedHumanoid.EvaluateStateMachine = false
	streamedHumanoid:SetAttribute("Ragdolled", true)
	streamedHumanoid:SetAttribute("RagdollRestoreStateMachine", true)
	world.DescendantAdded:Emit(streamedHumanoid)
	streamedHumanoid:SetAttribute("Ragdolled", false)
	assert(streamedHumanoid.EvaluateStateMachine, "late observer captured disabled evaluation as recovery default")
	ragdoll.Set(upgradedHumanoid, true)
	animatedJoint.Enabled = true
	runService.PreSimulation:Emit()
	assert(animatedJoint.Enabled, "observer independently rewrote server joint layout")
	animatedJoint.Enabled = false -- Restore the server's ragdoll state in this shared mock.
	-- Run the real victim LocalScript. Exercise remote/attribute ordering,
	-- stale releases, an already-disabled controller, death, and respawn.
	local controls = {controlsEnabled = true}
	function controls:Disable() self.controlsEnabled = false end
	function controls:Enable() self.controlsEnabled = true end
	local playerScripts = instance("Folder", "PlayerScripts", victim)
	local playerModule = instance("ModuleScript", "PlayerModule", playerScripts)
	local savedRequire = env.require
	env.require = function(module)
		if module == playerModule then return {GetControls = function() return controls end} end
		if module == ragdollModule then return clientRagdoll end
		return savedRequire(module)
	end
	local clientCharacter, clientHumanoid = character("LocalVictim", V.zero, false)
	world.DescendantAdded:Emit(clientHumanoid)
	players.LocalPlayer, victim.Character = victim, clientCharacter
	execute(sources.victimClient)
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 100, true)
	assert(not controls.controlsEnabled and clientHumanoid.State == "Physics", "victim did not surrender local controls and state")
	assert(not clientHumanoid.EvaluateStateMachine, "remote arriving before attributes left local humanoid forces active")
	clientHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 101, true)
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 100, false)
	assert(not controls.controlsEnabled, "stale remote released a newer capture")
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 101, false)
	assert(not controls.controlsEnabled, "release remote ignored replicated hold")
	clientHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	assert(controls.controlsEnabled and clientHumanoid.EvaluateStateMachine, "victim controls/state were not restored")
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 101, true)
	assert(controls.controlsEnabled, "duplicate completed start relocked controls")
	controls.controlsEnabled = false
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 102, true)
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 102, false)
	assert(not controls.controlsEnabled, "release enabled controls disabled by another system before capture")
	controls.controlsEnabled = true
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 103, true)
	clientHumanoid.Health = 0
	clientHumanoid.Died:Emit()
	assert(controls.controlsEnabled, "death left controls locked")
	clientHumanoid.Health = 100
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 104, true)
	victim.CharacterRemoving:Emit(clientCharacter)
	assert(controls.controlsEnabled and not clientHumanoid:GetAttribute("GrappleLocalPhysicsLock"), "respawn retained old lock")
	local newCharacter, newHumanoid = character("NewLocalVictim", V.zero, false)
	world.DescendantAdded:Emit(newHumanoid)
	victim.Character = newCharacter
	victim.CharacterAdded:Emit(newCharacter)
	remotes.GrappleVictimState.OnClientEvent:Emit(clientCharacter, 105, true)
	assert(controls.controlsEnabled, "old character remote locked respawn")
	victim.CharacterRemoving:Emit(newCharacter)
	victim.Character = victimCharacter
	env.require = savedRequire
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
	-- Missing root/Humanoid and silent deaths must recover without a Died event.
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	attackerHumanoid.Health = 100
	attackerRoot.Parent = nil
	local loadsBefore = attacker.LoadCharacterCount
	runService.Heartbeat:Emit(0.1)
	attacker.FailLoad = true
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attacker.LoadCharacterCount == loadsBefore, "failed load was reported as successful")
	attacker.FailLoad = false
	runService.Heartbeat:Emit(0.1)
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attacker.LoadCharacterCount == loadsBefore + 1, "missing-root respawn was not retried")
	attackerRoot.Parent = attacker.Character
	attackerRoot.Position = V.zero
	attackerHumanoid.Parent = nil
	runService.Heartbeat:Emit(0.1)
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attacker.LoadCharacterCount == loadsBefore + 2, "missing Humanoid blocked respawn")
	attackerHumanoid.Parent = attacker.Character
	-- An old watchdog must never reload a healthy replacement character.
	attackerRoot.Parent = nil
	runService.Heartbeat:Emit(0.1)
	attackerRoot.Parent = attacker.Character
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	assert(attacker.LoadCharacterCount == loadsBefore + 2, "watchdog reloaded a recovered character")

	local bombPhysics = execute(sources.bombPhysics)
	for _, offset in ipairs({V.new(10, -1.5, 0), V.new(8, 3, 5), V.new(0, -4, 0)}) do
		local velocity = bombPhysics.ThrowVelocity(offset, 196.2, 70, 6)
		local flight = (velocity.Y + math.sqrt(velocity.Y^2 - 2 * 196.2 * offset.Y)) / 196.2
		local landed = velocity * flight - V.new(0, 196.2 * flight^2 / 2, 0)
		assert(velocity.Y > 0 and (landed - offset).Magnitude < 0.001, "reachable bomb lob missed clicked point")
	end
	local distant = bombPhysics.ThrowVelocity(V.new(1000, 0, 0), 196.2, 70, 6)
	assert(math.abs(distant.Magnitude - 70) < 0.001 and distant.X > 0 and distant.Y > 0, "out-of-range bomb did not arc toward aim")
	local up = bombPhysics.Knockback(V.new(0, 2, 0), 8, 150)
	local right = bombPhysics.Knockback(V.new(5, 2, 0), 8, 150)
	local left = bombPhysics.Knockback(V.new(-5, 2, 0), 8, 150)
	assert(up.X == 0 and up.Z == 0 and up.Y > 100, "underfoot blast must launch vertically")
	assert(right.X > 80 and left.X < -80 and right.Y < right.X, "side blast must launch far, away, at a low angle")
	assert(bombPhysics.Knockback(V.new(9, 0, 0), 8, 150).Magnitude == 0, "blast exceeded radius")
	assert(bombPhysics.Knockback(V.zero, 8, 150).Y == 150, "coincident blast produced invalid direction")

	-- Exercise actual throw validation, five-second airborne fuse and explosion.
	services.Debris = {AddItem = function() end}
	services.TweenService = {Create = function() return {Play = function() end} end}
	env.TweenInfo = {new = function() return {} end}
	env.Enum.PartType = {Ball = "Ball"}
	env.Enum.SurfaceType = {Smooth = "Smooth"}
	remotes.ThrowBomb = instance("RemoteEvent", "ThrowBomb")
	local bombModule = instance("ModuleScript", "BombPhysics", storage.Modules)
	local previousRequire = env.require
	env.require = function(module)
		if module == bombModule then return bombPhysics end
		return previousRequire(module)
	end
	local attackerBackpack = instance("Backpack", "Backpack", attacker)
	local victimBackpack = instance("Backpack", "Backpack", victim)
	gun.Parent, reverseGun.Parent = attackerBackpack, victimBackpack
	attackerHumanoid:SetAttribute("Ragdolled", false)
	attackerHumanoid:RemoveTag("Ragdoll")
	attackerRoot.AssemblyLinearVelocity = V.zero
	world.Raycast = function() return nil end
	ragdoll.Set(attackerHumanoid, false)
	execute(sources.bombs)
	local bombTool = assert(attackerBackpack:FindFirstChild(config.bombToolName))
	assert(bombTool:FindFirstChild("Handle").Shape == "Ball", "bomb must be a sphere")
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	assert(not world:FindFirstChild("ThrownBomb"), "unequipped bomb accepted")
	bombTool.Parent = attacker.Character
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(0/0, 0, 0))
	assert(not world:FindFirstChild("ThrownBomb"), "invalid bomb aim accepted")
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	local thrown = assert(world:FindFirstChild("ThrownBomb"))
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	local count = 0
	for _, child in ipairs(world:GetChildren()) do if child.Name == "ThrownBomb" then count += 1 end end
	assert(count == 1, "bomb cooldown allowed duplicate throw")
	thrown.Touched:Emit(attackerRoot)
	assert(not thrown:FindFirstChild("BombStick"), "bomb stuck to thrower before leaving hand")
	thrown.Touched:Emit(victimRoot)
	local weld = assert(thrown:FindFirstChild("BombStick"), "bomb did not stick to humanoid part")
	assert(weld.Part0 == victimRoot and not thrown.Anchored and thrown.Massless, "sticking must follow character without anchoring or weighing it down")
	thrown.Touched:Emit(wall)
	assert(weld.Part0 == victimRoot, "second contact replaced the first sticky target")
	thrown.Position = V.new(-5, -2, 0)
	now += 4.99
	runService.Heartbeat:Emit(0.1)
	assert(not thrown.destroyed, "bomb detonated early")
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(10, 0, 0))
	count = 0
	for _, child in ipairs(world:GetChildren()) do if child.Name == "ThrownBomb" then count += 1 end end
	assert(count == 1, "bomb allowed a new throw before six seconds")
	now += 0.02
	runService.Heartbeat:Emit(0.1)
	assert(thrown.destroyed and attackerRoot.AssemblyLinearVelocity.X > 800, "blast did not deliver tenfold knockback")
	ragdoll.RefreshOwnership(attackerHumanoid)
	assert(attackerRoot.NetworkOwner == nil, "ownership audit stole bomb's temporary server simulation")
	assert(attackerHumanoid:HasTag("Ragdoll") and attackerHumanoid:GetAttribute("Ragdolled"), "bomb did not ragdoll its target")
	local lockedUntil = attackerHumanoid:GetAttribute("BombRagdollUntil")
	assert(math.abs(lockedUntil - now - 5) < 0.001, "bomb lock must last five seconds after impact")
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:GetAttribute("Ragdolled"), "manual recovery bypassed bomb lock")
	attackerHumanoid:RemoveTag("Ragdoll")
	ragdoll.Set(attackerHumanoid, false)
	assert(attackerHumanoid:HasTag("Ragdoll") and attackerHumanoid:GetAttribute("Ragdolled"), "another recovery path bypassed bomb lock")
	now = lockedUntil - 0.01
	ragdoll.RefreshOwnership(attackerHumanoid)
	assert(attackerRoot.NetworkOwner == attacker, "bomb server hold did not return standalone ragdoll to its player")
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:GetAttribute("Ragdolled"), "bomb lock ended early")
	now = lockedUntil + 0.01
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(not attackerHumanoid:GetAttribute("Ragdolled"), "player could not recover after five seconds")
	bombTool.Parent = attacker.Character
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(10, 0, 0))
	local swept = assert(world:FindFirstChild("ThrownBomb"))
	swept.Position = V.new(10, 0, 0)
	world.Raycast = function() return {Instance = wall, Position = V.new(5, 0, 0), Normal = V.new(-1, 0, 0)} end
	runService.Heartbeat:Emit(0.1)
	assert(swept:FindFirstChild("BombStick").Part0 == wall, "sweep missed first wall along flight path")
	print("PASS: four-player ownership/split repairs, rigid ragdoll roots, observer isolation, handoff/recapture, controls/respawn, momentum, ropes, bombs")
end

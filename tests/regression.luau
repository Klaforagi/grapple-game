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
			Health = 100, HipHeight = 2, EvaluateStateMachine = true, AutoRotate = true, PlatformStand = false, CanCollide = false, Massless = false, Transparency = 0,
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
	function methods:ApplyImpulse(impulse)
		self.ImpulseCount = (self.ImpulseCount or 0) + 1
		self.AssemblyLinearVelocity += impulse / self.AssemblyMass
	end
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
	function methods:EquipTool(tool)
		self:UnequipTools()
		tool.Parent = self.Parent
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
	local toolSetupModule = instance("ModuleScript", "GrappleToolSetup", storage.Modules)
	local world = instance("Workspace")
	world.Gravity = 196.2
	local hitParts = {}
	function world:GetPartBoundsInBox() return hitParts end
	function world:Raycast() return nil end
	local services = {Players = players, RunService = runService, ReplicatedStorage = storage, Workspace = world, PhysicsService = {}}
	services.StarterPack = instance("StarterPack", "StarterPack")
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
	for _, name in ipairs({"FireGrapple", "ChangeLength", "ToggleWallMode", "ToggleRagdoll", "ResetCharacter", "GrappledPlayer", "GrappledWall", "HasBeenGrappled", "GrappleVictimState", "StruggleInput", "StruggleProgress", "EquipRagdollTool"}) do
		remotes[name] = instance("RemoteEvent", name)
	end
	local ragdoll = execute(sources.ragdoll)
	local playedSounds = {}
	local toolSetup
	env.require = function(module)
		if module == configModule then return config end
		if module == remoteModule then return remotes end
		if module == ragdollModule then return ragdoll end
		if module == toolSetupModule then return toolSetup end
		if module == soundModule then return function(source, sound) table.insert(playedSounds, {source = source, sound = sound}) end end
		error("Unexpected require")
	end
	toolSetup = execute(sources.toolSetup)
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
	local attackerHumanoid = attacker.Character:FindFirstChildOfClass("Humanoid")
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
	local starterGun = instance("Tool", config.toolName, services.StarterPack)
	local starterScript = instance("LocalScript", "OldEquipController", starterGun)
	starterScript.Disabled = false
	execute(sources.server)
	assert(starterScript.Disabled and starterGun:GetAttribute("GrappleManagedTool"), "StarterPack gun was not prepared before cloning")
	assert(not handle.Anchored and not handle.CanCollide and handle.Massless, "gun parts were only prepared after firing")
	hitParts = {victimRoot}
	-- An overlap hit must not allow a player to shoot through a solid wall.
	local wall = instance("Part", "Wall", world)
	world.Raycast = function() return {Instance = wall, Position = V.new(0, 0, 5)} end
	fire()
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "grapple went through wall")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	world.Raycast = function() return nil end
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	fire()
	assert(victimHumanoid:GetAttribute("GrappledBy") == nil, "grapple-locked player fired the gun")
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	attackerHumanoid:AddTag("Ragdoll")
	attackerHumanoid:SetAttribute("Ragdolled", true)
	fire()
	assert(victimHumanoid:GetAttribute("GrappledBy") == attacker.UserId, "ragdolled player could not fire the gun")
	attackerHumanoid:RemoveTag("Ragdoll")
	attackerHumanoid:SetAttribute("Ragdolled", false)
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
	assert(victimHumanoid.State == "Physics" and victimHumanoid.PlatformStand and not victimHumanoid:GetStateEnabled("GettingUp"), "grappled victim is not held in passive physics state")
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
	assert(victimHumanoid:GetAttribute("Ragdolled") and not victimHumanoid.PlatformStand, "release left voluntary ragdoll unable to equip tools")
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
	local function collisionPair(character, a, b)
		for _, constraint in ipairs(character:FindFirstChild("GrappleSelfCollision"):GetChildren()) do
			if (constraint.Part0 == a and constraint.Part1 == b) or (constraint.Part0 == b and constraint.Part1 == a) then return constraint end
		end
		error("Missing collision pair")
	end
	local r6Torso, r6Limb1, r6Limb2 = r6:FindFirstChild("Torso"), r6:FindFirstChild("Limb1"), r6:FindFirstChild("Limb2")
	local oppositeLimbs = collisionPair(r6, r6Limb1, r6Limb2)
	assert(not oppositeLimbs.Enabled, "non-neighboring limbs still pass through each other")
	assert(collisionPair(r6, r6Torso, r6Limb1).Enabled, "joint neighbors can fight at their shared pivot")
	assert(collisionPair(r6, root6, r6Limb2).Enabled, "invisible root can collide with its own limbs")
	local nativeIgnore = instance("NoCollisionConstraint", "NativeLimbFilter", r6)
	nativeIgnore.Part0, nativeIgnore.Part1 = r6Limb1, r6Limb2
	r6.DescendantAdded:Emit(nativeIgnore)
	assert(not nativeIgnore.Enabled, "native self-collision filter defeated the new collision policy")
	ragdoll.Set(hum6, false)
	assert(oppositeLimbs.Enabled and nativeIgnore.Enabled, "normal self-collision filters were not restored")
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
	-- Native shoulders can use different attachment instances and reversed order.
	local socketShoulder0 = instance("Attachment", "SocketShoulder0", shoulder0)
	local shoulderBone = instance("Bone", "ShoulderBone", upgradedArm)
	local socketShoulder1 = instance("Attachment", "SocketShoulder1", shoulderBone)
	nativeSocket.Attachment0, nativeSocket.Attachment1 = socketShoulder1, socketShoulder0
	nativeSocket.MaxFrictionTorque = 67
	nativeSocket.LimitsEnabled, nativeSocket.TwistLimitsEnabled = true, true
	nativeSocket.UpperAngle, nativeSocket.TwistLowerAngle, nativeSocket.TwistUpperAngle = 15, -5, 5
	nativeSocket.Restitution = 0.3
	local extraSocket = instance("BallSocketConstraint", "ExtraShoulderBrace", upgradedTorso)
	extraSocket.Attachment0, extraSocket.Attachment1 = root0, socketShoulder1
	extraSocket.MaxFrictionTorque = 47
	ragdoll.Set(upgradedHumanoid, true)
	assert(not animatedJoint.Enabled and nativeSocket.Enabled, "upgraded avatar remained animated/stiff")
	local upgradedFolder = upgradedRig:FindFirstChild("GrappleRagdollJoints")
	assert(#upgradedFolder:GetChildren() == 1, "native avatar sockets duplicated")
	assert(not animatedRoot.Enabled and upgradedFolder:FindFirstChild("RagdollRootWeld").Enabled, "upgraded root remained animated")
	assert(nativeSocket.MaxFrictionTorque == 5, "high native socket friction was not replaced")
	assert(nativeSocket.UpperAngle == 95 and nativeSocket.TwistLowerAngle == -70 and nativeSocket.TwistUpperAngle == 70, "shoulder still permits excessive folding")
	assert(nativeSocket.Restitution == 0 and not extraSocket.Enabled, "extra socket or bouncy limits still restrict the ragdoll")
	upgradedHumanoid:SetAttribute("BombRagdollUntil", now + 5)
	assert(nativeSocket.MaxFrictionTorque == 0, "bomb retained pose-holding socket friction")
	ragdoll.Set(upgradedHumanoid, true)
	assert(nativeSocket.MaxFrictionTorque == 0, "repeated ragdoll reset blast friction")
	upgradedHumanoid:SetAttribute("BombRagdollUntil", nil)
	assert(nativeSocket.MaxFrictionTorque == 5, "voluntary ragdoll lost settling friction after blast stun")
	ragdoll.Set(upgradedHumanoid, false)
	assert(animatedJoint.Enabled and nativeSocket.Enabled, "native rig recovery changed socket defaults")
	assert(animatedRoot.Enabled and not upgradedFolder:FindFirstChild("RagdollRootWeld").Enabled and nativeSocket.MaxFrictionTorque == 67, "upgraded root/friction failed to restore")
	assert(extraSocket.Enabled and extraSocket.MaxFrictionTorque == 47, "extra native socket was not restored")
	assert(nativeSocket.UpperAngle == 15 and nativeSocket.TwistLowerAngle == -5 and nativeSocket.TwistUpperAngle == 5 and nativeSocket.Restitution == 0.3, "recovery lost native socket limits")
	-- Late native sockets must replace generated fallbacks, even while active.
	local forearm = instance("Part", "LeftLowerArm", upgradedRig)
	local elbow0 = instance("Attachment", "Elbow0", upgradedArm)
	local elbow1 = instance("Attachment", "Elbow1", forearm)
	local elbow = instance("AnimationConstraint", "LeftElbow", upgradedArm)
	elbow.Attachment0, elbow.Attachment1 = elbow0, elbow1
	upgradedHumanoid:SetAttribute("BombRagdollUntil", now + 5)
	ragdoll.Set(upgradedHumanoid, true)
	local fallback = assert(upgradedFolder:FindFirstChild("LeftElbow"))
	assert(fallback.UpperAngle == 80 and fallback.TwistUpperAngle == 10, "elbow retained excessive bend/twist")
	assert(not collisionPair(upgradedRig, forearm, upgradedTorso).Enabled, "forearm cannot collide with non-neighboring torso")
	assert(collisionPair(upgradedRig, forearm, upgradedArm).Enabled, "elbow neighbors can collide at the pivot")
	local fallbackA0, fallbackA1 = fallback.Attachment0, fallback.Attachment1
	local lateSocket = instance("BallSocketConstraint", "LeftElbowBallSocket", upgradedArm)
	lateSocket.Enabled, lateSocket.MaxFrictionTorque = false, 55
	upgradedRig.DescendantAdded:Emit(lateSocket)
	lateSocket.Attachment0, lateSocket.Attachment1 = elbow0, elbow1
	lateSocket:GetPropertyChangedSignal("Attachment1"):Emit()
	assert(fallback.destroyed and fallbackA0.destroyed and fallbackA1.destroyed, "late socket left duplicate fallback constraints")
	assert(lateSocket.Enabled and lateSocket.MaxFrictionTorque == 0 and not elbow.Enabled, "late socket was not activated with free blast joints")
	upgradedHumanoid:SetAttribute("BombRagdollUntil", nil)
	ragdoll.Set(upgradedHumanoid, false)
	assert(elbow.Enabled and not lateSocket.Enabled and lateSocket.MaxFrictionTorque == 55, "late socket adoption corrupted recovery state")
	-- Swap Player1/Player2 roles: the same ownership and recovery rules must apply.
	local reverseGun = instance("Tool", config.toolName, victimCharacter)
	local reverseHandle = instance("Part", "Handle", reverseGun)
	reverseHandle.Position = victimRoot.Position
	instance("Attachment", "FirePoint", reverseHandle)
	local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
	hitParts = {attackerRoot}
	now += 0.1
	remotes.FireGrapple.OnServerEvent:Emit(victim, attackerRoot.Position, victimRoot.Position)
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
	now += 1
	remotes.FireGrapple.OnServerEvent:Emit(attacker, V.new(0, 0, 100), V.new(0, 0, -100))
	local unequipRope = assert(wall:FindFirstChildWhichIsA("RopeConstraint"))
	-- An old Unequipped notification must release the rope without issuing a
	-- second inventory command against a gun that has already been reselected.
	gun.Unequipped:Emit()
	assert(unequipRope.destroyed and gun.Parent == attacker.Character, "rope cleanup put away a reselected gun")
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
	players.LocalPlayer = attacker
	local clientRagdoll = execute(sources.ragdoll)
	clientRagdoll.InitClient()
	assert(not victimHumanoid.EvaluateStateMachine, "remote victim retained humanoid forces")
	assert(attackerHumanoid.EvaluateStateMachine, "healthy character state machine was disabled")
	-- Exercise the real camera callback during accelerating falls, including
	-- a slow/mobile frame rate. Only the visual anchor may move.
	local previousCFrameNew = env.CFrame.new
	env.CFrame.new = function(position) return {Position = position, LookVector = identity.LookVector} end
	world.CurrentCamera = {CameraSubject = attackerHumanoid}
	local cameraStep = runService.renderBindings.GrappleRagdollCameraAnchor
	local originalRootPosition = attackerRoot.Position
	local originalRootVelocity = attackerRoot.AssemblyLinearVelocity
	local originalRootFrame = attackerRoot.CFrame
	for _, fps in ipairs({15, 30, 60, 144}) do
		attackerRoot.Position = V.new(0, 2000, 0)
		attackerHumanoid:SetAttribute("Ragdolled", true)
		local anchor = assert(world:FindFirstChild("RagdollCameraAnchor"))
		anchor.Position = anchor.CFrame.Position -- Mirror Roblox's CFrame -> Position property update.
		for frame = 1, fps * 4 do
			local t = frame / fps
			attackerRoot.Position = V.new(30 * t, 2000 - 100 * t - 0.5 * world.Gravity * t * t, 0)
			attackerRoot.AssemblyLinearVelocity = V.new(30, -100 - world.Gravity * t, 0)
			local velocity = attackerRoot.AssemblyLinearVelocity
			cameraStep(1 / fps)
			anchor.Position = anchor.CFrame.Position
			assert((attackerRoot.Position - anchor.Position).Magnitude <= 1.25001, "fast fall escaped the camera at " .. fps .. " FPS")
			assert(attackerRoot.AssemblyLinearVelocity == velocity and attackerRoot.CFrame == originalRootFrame, "camera follow modified body physics")
		end
		-- Resting sub-stud motion should still be filtered out.
		local restingAnchor = anchor.CFrame
		for frame = 1, fps do
			attackerRoot.Position = anchor.Position + V.new(0.2 * math.sin(frame), 0.1, 0)
			cameraStep(1 / fps)
			assert(anchor.CFrame == restingAnchor, "resting jitter moved the camera")
		end
		attackerHumanoid:SetAttribute("Ragdolled", false)
		assert(world.CurrentCamera.CameraSubject == attackerHumanoid, "recovery did not restore normal camera")
	end
	attackerRoot.Position, attackerRoot.AssemblyLinearVelocity = originalRootPosition, originalRootVelocity
	env.CFrame.new = previousCFrameNew
	world.CurrentCamera = nil
	-- Airborne voluntary entry gets one local-owner nudge, preserving travel.
	local savedEntryVelocity = attackerRoot.AssemblyLinearVelocity
	local savedEntrySpin = {}
	for _, part in ipairs(attacker.Character:GetChildren()) do
		if part:IsA("BasePart") then savedEntrySpin[part] = part.AssemblyAngularVelocity part.AssemblyAngularVelocity = V.zero end
	end
	attackerRoot.AssemblyLinearVelocity = V.new(8, 25, 0)
	attackerHumanoid:SetAttribute("RagdollExpectedOwner", 0)
	attackerHumanoid:SetAttribute("Ragdolled", true)
	runService.PreSimulation:Emit()
	assert(attackerRoot.AssemblyAngularVelocity.Magnitude == 0, "client kicked a server-owned ragdoll")
	attackerHumanoid:SetAttribute("RagdollExpectedOwner", attacker.UserId)
	runService.PreSimulation:Emit()
	assert(math.abs(attackerRoot.AssemblyAngularVelocity.Magnitude - 1.2) < 0.001, "airborne ragdoll entry stayed rigid")
	assert((attackerRoot.AssemblyLinearVelocity - V.new(8, 25, 0)).Magnitude == 0, "entry nudge changed jump/fall velocity")
	local entrySpin = attackerRoot.AssemblyAngularVelocity
	runService.PreSimulation:Emit()
	assert((attackerRoot.AssemblyAngularVelocity - entrySpin).Magnitude == 0, "entry nudge repeated every frame")
	attackerHumanoid:SetAttribute("Ragdolled", false)
	attackerRoot.AssemblyAngularVelocity, attackerRoot.AssemblyLinearVelocity = V.zero, V.zero
	attackerHumanoid:SetAttribute("Ragdolled", true)
	runService.PreSimulation:Emit()
	assert(attackerRoot.AssemblyAngularVelocity.Magnitude == 0, "resting ragdoll received an airborne nudge")
	attackerHumanoid:SetAttribute("Ragdolled", false)
	attackerRoot.AssemblyLinearVelocity = V.new(8, 25, 0)
	attackerHumanoid:SetAttribute("BombRagdollUntil", now + 5)
	attackerHumanoid:SetAttribute("Ragdolled", true)
	runService.PreSimulation:Emit()
	assert(attackerRoot.AssemblyAngularVelocity.Magnitude == 0, "client entry nudge conflicted with bomb launch")
	attackerHumanoid:SetAttribute("BombRagdollUntil", nil)
	attackerHumanoid:SetAttribute("Ragdolled", false)
	attackerRoot.AssemblyLinearVelocity = savedEntryVelocity
	for part, spin in pairs(savedEntrySpin) do part.AssemblyAngularVelocity = spin end
	victimRoot.AssemblyAngularVelocity = V.new(3, 2, 1)
	runService.PreSimulation:Emit()
	assert(victimRoot.AssemblyAngularVelocity.Magnitude > 0, "observer rewrote the physics owner's velocity")
	hum6:SetAttribute("Ragdolled", true)
	assert(not hum6.EvaluateStateMachine and not hum6.PlatformStand, "free ragdoll blocked hotbar tool equips")
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
	attackerHumanoid:SetAttribute("Ragdolled", true)
	now += 0.2
	toolClient.Fire(gun)
	assert(#remotes.FireGrapple.sent == 3, "ragdolled player could not fire the grapple gun")
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	now += 0.2
	toolClient.Fire(gun)
	assert(#remotes.FireGrapple.sent == 3, "grapple-locked player fired the grapple gun")
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	attackerHumanoid:SetAttribute("Ragdolled", false)
	local unequipsBefore = attackerHumanoid.UnequippedCount or 0
	input.InputBegan:Emit({UserInputType = "Keyboard", KeyCode = "One"}, true)
	assert(gun.Parent == attacker.Character and (attackerHumanoid.UnequippedCount or 0) == unequipsBefore, "grapple code hijacked the normal hotbar key")
	world.Raycast = function() return nil end
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
	-- Use a living character; the earlier victim fixture died in the death test.
	local equipPlayer = instance("Player", "EquipPlayer", players)
	local equipCharacter, equipHumanoid = character("EquipCharacter", V.zero, false)
	equipPlayer.Character = equipCharacter
	players.PlayerAdded:Emit(equipPlayer)
	local victimToolBackpack = instance("Backpack", "Backpack", equipPlayer)
	equipPlayer.ChildAdded:Emit(victimToolBackpack)
	local ragdollBomb = instance("Tool", config.bombToolName, victimToolBackpack)
	local ragdollGun = instance("Tool", config.toolName, victimToolBackpack)
	local legacyEquip = instance("LocalScript", "OldEquipController", ragdollGun)
	local legacyServer = instance("Script", "OldServerController", ragdollGun)
	local gunData = instance("ModuleScript", "GunData", ragdollGun)
	legacyEquip.Disabled, legacyServer.Disabled = false, false
	local gunHandle = instance("Part", "Handle", ragdollGun)
	gunHandle.Anchored, gunHandle.CanCollide = true, true
	ragdollGun.Enabled, ragdollGun.ManualActivationOnly = false, true
	ragdollGun.Equipped:Connect(function()
		-- Model the asset-only equip guard that the previous empty Tool mocks
		-- never exercised. It is not part of the repo's persistent controller.
		if not legacyEquip.Disabled and equipHumanoid:GetAttribute("Ragdolled") then equipHumanoid:UnequipTools() end
	end)
	victimToolBackpack.ChildAdded:Emit(ragdollGun)
	assert(legacyEquip.Disabled and legacyServer.Disabled and not gunData.Disabled, "legacy gun controllers were not isolated from module data")
	assert(not gunHandle.Anchored and not gunHandle.CanCollide and gunHandle.Massless, "unequipped gun retained unsafe physics")
	assert(ragdollGun.Enabled and not ragdollGun.ManualActivationOnly, "legacy activation flags were not cleared")
	local lateController = instance("LocalScript", "LateController", ragdollGun)
	ragdollGun.DescendantAdded:Emit(lateController)
	assert(lateController.Disabled, "late gun controller could reintroduce equip restrictions")
	local bombController = instance("LocalScript", "BombController", ragdollBomb)
	victimToolBackpack.ChildAdded:Emit(ragdollBomb)
	assert(not bombController.Disabled, "gun setup changed another tool")
	local clientSetup = execute(sources.toolSetup)
	local clientGun = instance("Tool", config.toolName)
	local clientScript = instance("LocalScript", "OldClientController", clientGun)
	local clientPart = instance("Part", "Handle", clientGun)
	clientPart.Anchored, clientPart.CanCollide = true, true
	clientSetup.Prepare(clientGun, false)
	assert(clientScript.Disabled, "client left an embedded equip controller running")
	assert(clientPart.Anchored and clientPart.CanCollide, "client independently changed tool physics")
	clientGun:Destroy()
	equipHumanoid:AddTag("Ragdoll")
	ragdoll.Set(equipHumanoid, true)
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.bombToolName, true)
	assert(ragdollBomb.Parent == equipCharacter and not equipHumanoid.PlatformStand, "ragdoll hotbar equip failed")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.toolName, true)
	assert(ragdollGun.Parent == equipCharacter and ragdollBomb.Parent == victimToolBackpack, "switching ragdoll tools failed")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.toolName, true)
	assert(ragdollGun.Parent == equipCharacter, "duplicate/late equip request put the grapple away")
	assert(not equipHumanoid.EvaluateStateMachine and equipHumanoid:GetAttribute("Ragdolled"), "equip woke up the ragdoll")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.toolName, false)
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.toolName, false)
	assert(ragdollGun.Parent == victimToolBackpack, "explicit unequip toggled the grapple back on")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.bombToolName, true)
	equipHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	ragdoll.Set(equipHumanoid, true)
	assert(ragdollBomb.Parent ~= equipCharacter, "grapple lock did not unequip an already-ragdolled victim")
	ragdollBomb.Parent = victimToolBackpack
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, config.bombToolName, true)
	assert(ragdollBomb.Parent == victimToolBackpack, "grapple-locked victim equipped a tool")
	ragdollBomb.Parent = equipCharacter
	equipCharacter.ChildAdded:Emit(ragdollBomb)
	assert(ragdollBomb.Parent ~= equipCharacter, "grappled victim could equip a tool")
	equipHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	ragdoll.Set(equipHumanoid, false)
	equipHumanoid:RemoveTag("Ragdoll")
	-- The HUD buttons must leave the native hotbar visible and its keys alone.
	local nativeBackpackEnabled = true
	services.StarterGui.GetCoreGuiEnabled = function() return nativeBackpackEnabled end
	services.StarterGui.SetCoreGuiEnabled = function(_, _, enabled) nativeBackpackEnabled = enabled end
	local equipActions = {}
	services.ContextActionService = {
		BindActionAtPriority = function(_, name, callback) equipActions[name] = callback end,
		UnbindAction = function(_, name) equipActions[name] = nil end,
	}
	env.Enum.CoreGuiType = {Backpack = "Backpack"}
	env.Enum.ContextActionResult = {Pass = "Pass", Sink = "Sink"}
	env.Enum.ContextActionPriority = {High = {Value = 3000}}
	env.Enum.UserInputState = {Begin = "Begin", End = "End"}
	players.LocalPlayer = equipPlayer
	local equipClient = execute(sources.ragdollToolClient)
	assert(nativeBackpackEnabled and next(equipActions) == nil, "normal hotbar was overridden")
	equipHumanoid:SetAttribute("Ragdolled", true)
	assert(nativeBackpackEnabled and next(equipActions) == nil, "ragdoll hid or overrode the native hotbar")
	local requestCount = #(remotes.EquipRagdollTool.sent or {})
	input.InputBegan:Emit({UserInputType = "Keyboard", KeyCode = "One"}, true)
	assert(#(remotes.EquipRagdollTool.sent or {}) == requestCount, "number key also sent a HUD equip request")
	-- Model the native Backpack transfer; the ragdoll guard must accept it.
	ragdollGun.Parent = equipCharacter
	equipCharacter.ChildAdded:Emit(ragdollGun)
	ragdollGun.Equipped:Emit()
	assert(ragdollGun.Parent == equipCharacter, "native hotbar equip was rejected during free ragdoll")
	ragdollGun.Parent = victimToolBackpack
	equipClient.Select(config.toolName)
	assert(#remotes.EquipRagdollTool.sent == requestCount + 1, "HUD emitted zero/multiple equip requests")
	local request = remotes.EquipRagdollTool.sent[requestCount + 1]
	assert(request[1] == config.toolName and request[2] == true, "HUD did not request explicit grapple equip")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, unpack(request))
	assert(ragdollGun.Parent == equipCharacter, "HUD-to-server grapple equip failed")
	equipClient.Select(config.toolName) -- Same call as the touch/HUD button.
	request = remotes.EquipRagdollTool.sent[requestCount + 2]
	assert(request[2] == false, "HUD button did not request explicit put-away")
	remotes.EquipRagdollTool.OnServerEvent:Emit(equipPlayer, unpack(request))
	equipHumanoid:SetAttribute("GrappleLocalPhysicsLock", true)
	equipClient.Select(config.toolName)
	assert(#remotes.EquipRagdollTool.sent == requestCount + 2, "local capture lock allowed an equip")
	equipHumanoid:SetAttribute("GrappleLocalPhysicsLock", nil)
	equipHumanoid:SetAttribute("Ragdolled", false)
	assert(nativeBackpackEnabled and next(equipActions) == nil, "recovery did not restore native hotbar")
	nativeBackpackEnabled = false
	equipHumanoid:SetAttribute("Ragdolled", true)
	equipHumanoid:SetAttribute("Ragdolled", false)
	assert(not nativeBackpackEnabled, "restored a hotbar previously disabled by another system")
	nativeBackpackEnabled = true
	equipHumanoid:SetAttribute("Ragdolled", true)
	equipHumanoid.Health = 0
	equipHumanoid.Died:Emit()
	assert(nativeBackpackEnabled and next(equipActions) == nil, "death retained the ragdoll hotbar")
	equipPlayer.CharacterRemoving:Emit(equipCharacter)
	equipPlayer.Character = nil
	equipClient.Select(config.toolName)
	assert(#remotes.EquipRagdollTool.sent == requestCount + 2, "removed character sent an equip request")
	players.LocalPlayer = attacker
	equipCharacter:Destroy()
	ragdollBomb:Destroy()
	now += 1
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:HasTag("Ragdoll"), "ready player could not ragdoll")
	assert(gun.Parent == attacker.Character, "non-grappled ragdoll unequipped the grapple gun")
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
	local verticalTumble = bombPhysics.TumbleVelocity(V.new(0, 150, 0), 2.5)
	assert(math.abs(verticalTumble.Magnitude - 2.5) < 0.001, "vertical blast has no tumble")
	local rightTumble = bombPhysics.TumbleVelocity(V.new(50, 150, 0), 2.5)
	local leftTumble = bombPhysics.TumbleVelocity(V.new(-50, 150, 0), 2.5)
	assert(rightTumble.Z < 0 and leftTumble.Z > 0, "blast tumble does not pitch away from explosion")
	assert(bombPhysics.TumbleVelocity(V.zero, 1000).Magnitude == 4, "tumble configuration can create excessive spin")
	assert(bombPhysics.TumbleVelocity(V.zero, 0).Magnitude == 0, "tumble cannot be disabled")
	local motionVelocity = V.new(20, 160, 0)
	for _, extent in ipairs({1, 1000}) do
		local bodies = {
			{position = V.zero, mass = 30, isRoot = true},
			{position = V.new(-3, 1, 0) * extent, mass = 2},
			{position = V.new(1, -3, 1) * extent, mass = 4},
		}
		bombPhysics.LaunchMotion(bodies, motionVelocity, 3.5, 3)
		local momentum = V.zero
		for _, body in ipairs(bodies) do
			momentum += body.velocity * body.mass
			assert((body.velocity - motionVelocity).Magnitude <= 12.001, "limb kick is unbounded on large avatars")
			assert(body.angular.Magnitude <= 5.001, "limb spin is unbounded")
		end
		assert((momentum / 36 - motionVelocity).Magnitude < 0.001, "tumble changed the center-of-mass launch trajectory")
		assert((bodies[2].velocity - bodies[3].velocity).Magnitude > 0.1, "limbs still receive identical travel velocities")
		assert(bodies[1].angular:Dot(bodies[2].angular) > 0, "limb spin cancels the torso's tumble")
	end
	local orbitBodies = {{position = V.new(0, 3, 0), mass = 5}, {position = V.new(0, -3, 0), mass = 5}}
	bombPhysics.LaunchMotion(orbitBodies, V.new(0, 150, 0), 3, 0)
	assert(orbitBodies[1].velocity.Z == 9 and orbitBodies[2].velocity.Z == -9, "tumble lacks compatible orbital limb velocity")
	bombPhysics.LaunchMotion(orbitBodies, motionVelocity, 0, 0)
	for _, body in ipairs(orbitBodies) do
		assert((body.velocity - motionVelocity).Magnitude == 0 and body.angular.Magnitude == 0, "disabled launch motion still adds tumble")
	end
	for _, offset in ipairs({V.new(10, -1.5, 0), V.new(8, 3, 5), V.new(0, -4, 0)}) do
		local velocity = bombPhysics.ThrowVelocity(offset, 196.2, 70, 6)
		local flight = (velocity.Y + math.sqrt(velocity.Y^2 - 2 * 196.2 * offset.Y)) / 196.2
		local landed = velocity * flight - V.new(0, 196.2 * flight^2 / 2, 0)
		assert(velocity.Y > 0 and (landed - offset).Magnitude < 0.001, "reachable bomb lob missed clicked point")
	end
	local distant = bombPhysics.ThrowVelocity(V.new(1000, 0, 0), 196.2, 70, 6)
	assert(math.abs(distant.Magnitude - 70) < 0.001 and distant.X > 0 and distant.Y > 0, "out-of-range bomb did not arc toward aim")
	local function blastVelocity(offset)
		return bombPhysics.Knockback(offset, config.bombRadius, world.Gravity, config.bombLaunchHeight, config.bombLaunchDistance)
	end
	local up, right, left = blastVelocity(V.new(0, 2, 0)), blastVelocity(V.new(5, 2, 0)), blastVelocity(V.new(-5, 2, 0))
	assert(up.X == 0 and up.Z == 0, "underfoot blast must launch vertically")
	assert(right.X > 0 and left.X < 0, "side blasts must launch away from center")
	assert(blastVelocity(V.new(9, 0, 0)).Magnitude == 0, "blast exceeded radius")
	local function blastRange(velocity)
		return V.new(velocity.X, 0, velocity.Z).Magnitude * 2 * velocity.Y / world.Gravity
	end
	local centerRange = blastRange(blastVelocity(V.zero))
	local middleRange = blastRange(blastVelocity(V.new(config.bombRadius / 2, 0, 0)))
	local edgeRange = blastRange(blastVelocity(V.new(config.bombRadius, 0, 0)))
	assert(centerRange == 0, "blast at center must have no horizontal travel")
	assert(math.abs(middleRange - config.bombLaunchDistance / 2) < 0.001, "mid-radius blast must launch halfway")
	assert(math.abs(edgeRange - config.bombLaunchDistance) < 0.001, "edge blast must launch the full configured distance")
	for _, offset in ipairs({V.zero, V.new(0, 2, 0), V.new(5, 2, 0), V.new(8, 0, 0), V.new(0, -8, 0)}) do
		local velocity = blastVelocity(offset)
		local height = velocity.Y * velocity.Y / (2 * world.Gravity)
		local range = blastRange(velocity)
		assert(height >= 50 and height <= 100 and range <= config.bombLaunchDistance + 0.001, "blast trajectory exceeded its configured target")
	end

	-- Exercise actual throw validation, 3.5-second fuse, cooldown, and explosion.
	services.Debris = {AddItem = function() end}
	services.TweenService = {Create = function() return {Play = function() end} end}
	env.TweenInfo = {new = function() return {} end}
	env.Enum.PartType = {Ball = "Ball"}
	env.Enum.SurfaceType = {Smooth = "Smooth"}
	local soundsFolder = instance("Folder", "Sounds", storage)
	local explosionSound = instance("Sound", "Explode", soundsFolder)
	explosionSound.TimeLength = 2
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
	attackerHumanoid:SetAttribute("Ragdolled", true)
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	assert(not world:FindFirstChild("ThrownBomb"), "grapple-locked player threw a bomb")
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	local thrown = assert(world:FindFirstChild("ThrownBomb"))
	attackerHumanoid:SetAttribute("Ragdolled", false)
	local bombHandle = bombTool:FindFirstChild("Handle")
	assert(bombHandle.Transparency == 1 and not bombTool.Enabled, "held bomb did not disappear during cooldown")
	local threwAt = now
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(100, 0, 0))
	local count = 0
	for _, child in ipairs(world:GetChildren()) do if child.Name == "ThrownBomb" then count += 1 end end
	assert(count == 1, "bomb cooldown allowed duplicate throw")
	thrown.Touched:Emit(attackerRoot)
	assert(not thrown:FindFirstChild("BombStick"), "bomb stuck to thrower before leaving hand")
	now += 1
	thrown.Touched:Emit(attackerRoot)
	thrown.Touched:Emit(bombHandle)
	thrown.Touched:Emit(handle)
	local lateAccessory = instance("Part", "LateAccessory", attacker.Character)
	attacker.Character.DescendantAdded:Emit(lateAccessory)
	lateAccessory.Parent = world
	thrown.Touched:Emit(lateAccessory)
	local ghost = instance("Part", "CameraOrEffect", world)
	ghost.CanCollide = false
	thrown.Touched:Emit(ghost)
	assert(not thrown:FindFirstChild("BombStick"), "bomb stuck to thrower/tools/effect after old grace period")
	thrown.Touched:Emit(victimRoot)
	local weld = assert(thrown:FindFirstChild("BombStick"), "bomb did not stick to humanoid part")
	assert(weld.Part0 == victimRoot and not thrown.Anchored and thrown.Massless, "sticking must follow character without anchoring or weighing it down")
	thrown.Touched:Emit(wall)
	assert(weld.Part0 == victimRoot, "second contact replaced the first sticky target")
	thrown.Position = V.new(-5, -2, 0)
	now = threwAt + 3.49
	runService.Heartbeat:Emit(0.1)
	assert(not thrown.destroyed, "bomb detonated early")
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(10, 0, 0))
	count = 0
	for _, child in ipairs(world:GetChildren()) do if child.Name == "ThrownBomb" then count += 1 end end
	assert(count == 1, "bomb allowed a new throw before six seconds")
	now += 0.02
	runService.Heartbeat:Emit(0.1)
	assert(thrown.destroyed, "bomb missed 3.5-second fuse")
	assert(attackerRoot.AssemblyLinearVelocity.Magnitude == 0, "launch ran before the ragdoll assembly rebuild")
	for _, joint in ipairs(attacker.Character:GetDescendants()) do
		if joint:IsA("Motor6D") and joint:GetAttribute("GrappleRagdollJoint") then
			assert(not joint.Enabled, "bomb launched with animated limb joints still enabled")
		end
	end
	assert(playedSounds[#playedSounds].sound == explosionSound and playedSounds[#playedSounds].source.Name == "BombBlast", "explosion sound did not play at blast")
	-- The engine puts an unequipped tool into Backpack; mirror that in this mock.
	bombTool.Parent = attackerBackpack
	local splitLimb = attacker.Character:FindFirstChild("Limb1")
	for _, part in ipairs(attacker.Character:GetChildren()) do
		if part:IsA("BasePart") and part ~= splitLimb then part.AssemblyRootPart = attackerRoot end
	end
	local previousRootImpulses = attackerRoot.ImpulseCount or 0
	-- Existing violent spin must be replaced, not compounded by another blast.
	attackerRoot.AssemblyAngularVelocity = V.new(100, 100, 100)
	splitLimb.AssemblyAngularVelocity = V.new(-100, -100, -100)
	now += 1 / 60
	runService.Heartbeat:Emit(1 / 60)
	local launched = attackerRoot.AssemblyLinearVelocity
	assert(launched.X > 0 and launched.Y^2 / (2 * world.Gravity) >= 50 and launched.Magnitude < 200, "blast was missing or overpowered")
	assert(attackerRoot.ImpulseCount == previousRootImpulses + 1, "shared assembly received one impulse per part")
	assert((splitLimb.AssemblyLinearVelocity - launched).Magnitude < 0.001, "newly split ragdoll limb missed launch")
	local expectedTumble = bombPhysics.TumbleVelocity(launched, config.bombTumbleSpeed)
	assert((attackerRoot.AssemblyAngularVelocity - expectedTumble).Magnitude < 0.001, "torso did not start a bounded tumble during launch")
	assert((splitLimb.AssemblyAngularVelocity - expectedTumble).Magnitude < 0.001, "co-located mock assemblies received opposing spin")
	attackerRoot.AssemblyAngularVelocity = V.new(0.2, 0.3, 0.4)
	runService.Heartbeat:Emit(1 / 60)
	assert((attackerRoot.AssemblyAngularVelocity - V.new(0.2, 0.3, 0.4)).Magnitude < 0.001, "bomb continuously forced ragdoll spin")
	for _, part in ipairs(attacker.Character:GetChildren()) do
		if part:IsA("BasePart") then part.AssemblyRootPart = nil end
	end
	ragdoll.RefreshOwnership(attackerHumanoid)
	assert(attackerRoot.NetworkOwner == nil, "ownership audit stole bomb's temporary server simulation")
	assert(attackerHumanoid:HasTag("Ragdoll") and attackerHumanoid:GetAttribute("Ragdolled"), "bomb did not ragdoll its target")
	local lockedUntil = attackerHumanoid:GetAttribute("BombRagdollUntil")
	assert(math.abs(lockedUntil - (threwAt + 3.51) - 5) < 0.001, "bomb lock must last five seconds after impact")
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:GetAttribute("Ragdolled"), "manual recovery bypassed bomb lock")
	attackerHumanoid:RemoveTag("Ragdoll")
	ragdoll.Set(attackerHumanoid, false)
	assert(attackerHumanoid:HasTag("Ragdoll") and attackerHumanoid:GetAttribute("Ragdolled"), "another recovery path bypassed bomb lock")
	now = threwAt + config.bombCooldown - 0.01
	runService.Heartbeat:Emit(0.1)
	assert(bombHandle.Transparency == 1 and not bombTool.Enabled, "held bomb returned before cooldown ended")
	now += 0.02
	runService.Heartbeat:Emit(0.02)
	assert(bombHandle.Transparency == 0 and bombTool.Enabled, "held bomb did not return at cooldown end")
	now = lockedUntil - 0.01
	ragdoll.RefreshOwnership(attackerHumanoid)
	assert(attackerRoot.NetworkOwner == attacker, "bomb server hold did not return standalone ragdoll to its player")
	remotes.ToggleRagdoll.OnServerEvent:Emit(attacker)
	assert(attackerHumanoid:GetAttribute("Ragdolled"), "bomb lock ended early")
	now = lockedUntil + 0.01
	runService.Heartbeat:Emit(0.02)
	assert(not attackerHumanoid:GetAttribute("Ragdolled") and attackerHumanoid.EvaluateStateMachine, "bomb victim did not automatically recover")
	bombTool.Parent = attacker.Character
	remotes.ThrowBomb.OnServerEvent:Emit(attacker, V.new(10, 0, 0))
	local swept = assert(world:FindFirstChild("ThrownBomb"))
	local sweptAt = now
	swept.Position = V.new(10, 0, 0)
	wall.CanCollide = true
	world.Raycast = function() return {Instance = wall, Position = V.new(5, 0, 0), Normal = V.new(-1, 0, 0)} end
	runService.Heartbeat:Emit(0.1)
	assert(swept:FindFirstChild("BombStick").Part0 == wall, "sweep missed first wall along flight path")
	-- An explosion must release a grapple, preserve voluntary ragdolls, and
	-- replace excessive existing velocity instead of adding more energy.
	world.Raycast = function() return nil end
	local blastTarget, blastHumanoid, blastRoot = character("GrappledBlastTarget", V.new(4, 0, 0), true)
	local manualTarget, manualHumanoid = character("ManualBlastTarget", V.new(3, 0, 0), false)
	manualHumanoid:AddTag("Ragdoll")
	ragdoll.Set(manualHumanoid, true)
	bombTool.Parent = attackerBackpack
	gun.Parent = attacker.Character
	hitParts = {blastRoot}
	fire()
	assert(blastHumanoid:GetAttribute("GrappledBy") == attacker.UserId, "blast test failed to create tether")
	attackerRoot.AssemblyLinearVelocity = V.new(2000, 2000, 0)
	now = sweptAt + config.bombFuse + 0.01
	runService.Heartbeat:Emit(0.02)
	assert(not gun:GetAttribute("HasGrappled") and not blastRoot:FindFirstChildWhichIsA("RopeConstraint"), "blast retained grapple tether")
	now += 1 / 60
	runService.Heartbeat:Emit(1 / 60)
	assert(attackerRoot.AssemblyLinearVelocity.Magnitude < 200 and blastRoot.AssemblyLinearVelocity.Magnitude > 100, "repeat launch stacked speed or failed to launch grappled NPC")
	for _, fn in ipairs(delayed) do fn() end table.clear(delayed)
	now += config.bombRagdollDuration + 0.01
	runService.Heartbeat:Emit(0.1)
	assert(not blastHumanoid:GetAttribute("Ragdolled"), "grapple-created ragdoll remained stuck after blast stun")
	assert(manualHumanoid:GetAttribute("Ragdolled"), "blast recovery removed a voluntary ragdoll")
	-- The client obeys server cooldown state but only debounces unacknowledged
	-- requests, so a rejected throw does not start a phantom six-second cooldown.
	bombTool.Parent = attacker.Character
	execute(sources.bombClient)
	attackerHumanoid:SetAttribute("Ragdolled", true)
	bombTool.Activated:Emit()
	assert(#remotes.ThrowBomb.sent == 1, "bomb client did not send equipped throw")
	bombTool.Activated:Emit()
	assert(#remotes.ThrowBomb.sent == 1, "bomb client failed to debounce input")
	now += 0.2
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", true)
	bombTool.Activated:Emit()
	assert(#remotes.ThrowBomb.sent == 1, "grapple-locked player threw a bomb")
	attackerHumanoid:SetAttribute("GrapplePhysicsLocked", nil)
	now += 0.2
	bombTool.Activated:Emit()
	assert(#remotes.ThrowBomb.sent == 2, "unacknowledged throw caused full client cooldown")
	bombTool.Enabled = false
	bombTool:SetAttribute("BombCoolingDown", true)
	now += 0.2
	bombTool.Activated:Emit()
	assert(#remotes.ThrowBomb.sent == 2, "bomb client ignored authoritative cooldown")
	print("PASS: bounded fall camera at 15/30/60/144 FPS, resting camera stability, four-player ownership, ragdolls, handoff/controls, momentum, ropes, bombs")
end

return {

	--[[
	+------------------------------------------------+
	|                   TOOL SETTINGS                |
	+------------------------------------------------+
	]]


	toolName = "Grapple Gun", -- Make sure this is the exact same name as the tool
	toolIcon = "rbxassetid://91010954183348", -- Roblox Backpack/hotbar icon
	
	debugMode = false, -- Visible hitbox, and print statements for debugging
	--[[
	NOTE:
	I put this since some of the scripts reference 
	the name of the grapple to detect if the player
	has the tool equipped or not.
	
	]]

	--[[
	+------------------------------------------------+
	|                   HOOK SETTINGS                |
	+------------------------------------------------+
	]]

	-- Min Hook distance
	minRopeLength = 1,
	-- Unupgraded hook distance. UpgradeCatalog raises this. Rank 10 is 300.
	-- Wall mode uses three times the player's current hook distance.
	maxRopeLength = 60,
	-- Click aim looks this far for a surface. It is not the hook's travel distance.
	-- Stopping the ray at the hook range turns a far ground click into a point in
	-- the air, and the gun below the camera then fires upward.
	aimRayLength = 100000,
	-- Player grapples persist until released, escaped, or a character leaves/dies.
	-- Unupgraded hook speed. UpgradeCatalog raises this. Rank 10 is 150.
	HookSpeed = 40, -- Studs per second
	-- The cooldown after it unhooks
	GrappleCooldown = 0.1,
	playerReleaseCooldown = 0.75, -- Ignore another click or tap briefly after catching a player
	playerOwnershipReleaseDelay = 0.2, -- Keep the last simulator and victim controls locked after detaching
	playerReleaseRagdollDuration = 1, -- Click/tap release keeps an auto-ragdolled victim loose to preserve momentum
	
	
	
	HitboxSize = Vector3.new(.5,.5,.5), -- Hook hitbox size

	--[[
	+------------------------------------------------+
	|                   TETHER SETTINGS              |
	+------------------------------------------------+
	]]
	
	playerTetherDuration = 20, -- Unupgraded seconds. UpgradeCatalog rank 10 is 60.
	-- Blue spawn bubble on the living character. SpawnLocation.Duration stays 0
	-- so the engine bubble cannot attach to the ragdoll corpse.
	spawnShieldSeconds = 6,
	-- Paid escape from a tether. The Robux button shows the price and does not
	-- prompt until escapeRobuxProductId is a real 9-Robux developer product.
	escapeShieldSeconds = 6,
	escapeCoinCost = 30,
	escapeRobuxPrice = 9,
	escapeRobuxProductId = 0,

	--[[
	+------------------------------------------------+
	|                   EXTRA			             |
	+------------------------------------------------+
	]]

	-- Extra (not in the order but thought I'd include it)
	GrappleToWalls = false,
	playerCollisionsEnabled = true, -- Players collide even while grappling/ragdolled; false restores pass-through

	-- Uses speed * time to calculate the distance
	GrapplingTime = 15,
	GrapplingSpeed = 15,
	
	grappleGravity = Vector3.new(0,0,0), -- Change the Y axis if you want the hook to be affected by gravity, ex: Vector3.new(0,-50,0)
	
	-- Q/E directly changes the permanent rope length in both target modes.
	ropeLengthFraction = 0.05, -- 5% of current length per press / held control tick
	ropeReelInterval = 1 / 15, -- Repeat held reel input at half the previous 30 Hz rate
	playerMinDragDistance = 4, -- Prevent bodies being forced into the gun
	playerReelVictimPullSpeed = 22, -- Minimum victim speed toward the grappler while shortening
	playerReelVictimMaxBoost = 30, -- Maximum velocity added by one accepted reel input
	capsuleCaptureDistance = 12, -- Victim must be this close to the Trigger Part
	capsulePromptDistance = 10,
	capsuleDamagePerSecond = 5,
	capsuleRescueShieldSeconds = 1,

	bombToolName = "Bomb",
	bombToolIcon = "rbxassetid://17724514739", -- Roblox Backpack/hotbar icon
	pushToolName = "Push",
	pushToolIcon = "rbxassetid://7925887190", -- Roblox Backpack/hotbar icon
	pushRange = 6.5, -- Studs forward; walls block the push
	pushWidth = 8,
	pushHeight = 6,
	pushCooldown = 4,
	pushActiveDuration = 0.35,
	pushMaxMovementLead = 2, -- Maximum extra forward reach for movement replication delay
	pushRagdollDuration = 5,
	pushSpeed = 35, -- Outward knockdown speed, studs/second (capped at 40)
	flopCooldown = 1.8,
	flopMaxSpeed = 22, -- Flops are only available while moving slowly
	flopHorizontalSpeed = 24,
	flopUpSpeed = 42,
	flopLimbKickSpeed = 7,
	flopSpinSpeed = 30, -- Radians/sec of the shoulder-axis roll; a short hop should land on the other side
	flopSpinCap = 42,
	bombFuse = 3.5, -- Seconds from throw, including time in flight
	bombCooldown = 6, -- Seconds after throwing before another throw
	bombRadius = 8, -- Root-to-explosion distance in studs
	bombLaunchHeight = 82, -- Studs above impact position in unobstructed flight; edge hits ~57
	bombLaunchDistance = 200, -- Horizontal studs back to impact height; directly underneath launches vertically
	bombTumbleSpeed = 3.5, -- Whole-body rotation in radians/sec, capped at 4
	bombLimbKickSpeed = 3, -- Relative limb kick in studs/sec, capped at 6; set both motion settings to 0 to disable
	bombDebugRagdoll = false, -- Enable to print server/client joint diagnostics after each blast
	bombRagdollDuration = 5, -- Each hit restarts stun; automatic recovery unless already voluntarily ragdolled
	bombThrowSpeed = 70,
	bombArcHeight = 6, -- Arc rises this far above the higher of hand and target
	
	ragdollRelease_Cooldown = 2, -- Seconds before a ragdoll you started yourself can be turned off
	ragdollToggle_Cooldown = 0.5, -- Seconds after standing up before ragdoll can be triggered again
	fallRagdollDistance = 40, -- Downward studs required; a jump is shorter than this and does not count
	fallRagdollDuration = 3, -- Minimum ragdoll time after a long fall, starting the moment of landing


	--[[
	+------------------------------------------------+
	|                   KEYBINDS	                 |
	+------------------------------------------------+
	]]

	
	shortenRope = Enum.KeyCode.Q,
	lengthenRope = Enum.KeyCode.E,
	ragdollKeybind = Enum.KeyCode.R,
	toggleWallMode = Enum.KeyCode.X,

	
	--[[
	+------------------------------------------------+
	|                   MOUSE ICON	                 |
	+------------------------------------------------+
	]]
	CustomCursorsEnabled = false,
	CustomCursorIcon = "rbxassetid://4727466020",
	GrappleInUseIcon = "rbxassetid://93965605308642",
	MouseObstructedIcon = "rbxassetid://132098868187033", -- Icon if mouse is obstructed or if it's in use

}

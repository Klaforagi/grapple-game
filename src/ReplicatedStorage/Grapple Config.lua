return {

	--[[
	+------------------------------------------------+
	|                   TOOL SETTINGS                |
	+------------------------------------------------+
	]]


	toolName = "Grapple Gun", -- Make sure this is the exact same name as the tool
	
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
	minRopeLength = 0.1,
	-- Max Hook distance
	maxRopeLength = 500,
	-- How long the grapple should be
	GrappleTime = 30, -- In seconds
	-- How fast the hook travels
	HookSpeed = 80, -- Studs per second
	-- The cooldown after it unhooks
	GrappleCooldown = 0.1,
	
	
	
	HitboxSize = Vector3.new(.5,.5,.5), -- Hook hitbox size

	--[[
	+------------------------------------------------+
	|                   STRUGGLE SETTINGS            |
	+------------------------------------------------+
	]]
	
	--[[
	I made the struggle randomized so you
	need to press the key a certain amount of times 
	to be able to get free of the grasp, if you want it 
	to be just one value and not randomized
	then make the min and max the same value
	]]
	
	
	minStruggleValue = 25,
	maxStruggleValue = 30,
	
	struggleIncrement = 1, -- How much struggle value it will add for each time the key is clicked
	
	struggleDecrease = true, -- Make this false if you dont want the struggle to slowly decrease
	struggleDecreaseAmt = 1, -- By how much the struggle value decreases
	struggleDecreaseInterval = 1, -- How often the struggle will decrease

	--[[
	+------------------------------------------------+
	|                   EXTRA			             |
	+------------------------------------------------+
	]]

	-- Extra (not in the order but thought I'd include it)
	GrappleToWalls = false,

	-- Uses speed * time to calculate the distance
	GrapplingTime = 15,
	GrapplingSpeed = 15,
	
	grappleGravity = Vector3.new(0,0,0), -- Change the Y axis if you want the hook to be affected by gravity, ex: Vector3.new(0,-50,0)
	
	ropeLengthSpeed = 10000, -- In studs, The interval on how fast the rope length should change
	
	ragdollToggle_Cooldown = 2, -- In seconds, how long before the player can toggle ragdoll again


	--[[
	+------------------------------------------------+
	|                   KEYBINDS	                 |
	+------------------------------------------------+
	]]

	
	struggleKeybind = Enum.KeyCode.Space,
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

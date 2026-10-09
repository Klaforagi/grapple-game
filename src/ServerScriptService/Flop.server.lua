local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage:WaitForChild("GrappleConfig"))
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local Motion = require(Storage.Modules:WaitForChild("FlopMotion"))
local lastRequest = {}
Remotes.Flop.OnServerEvent:Connect(function(player, direction)
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < (Config.flopCooldown or 2.2) then return end
	lastRequest[player] = now
	if typeof(direction) ~= "Vector3" then return end
	for _, value in ipairs({direction.X, direction.Y, direction.Z}) do
		if value ~= value or math.abs(value) > 2 then return end
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then return end
	direction = direction.Unit
	local character = player.Character
	if not Motion.CanFlop(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local owner = root:GetNetworkOwner()
	-- Choose once on the server so whichever client simulates the body receives
	-- the same bounded kick, with varied forward/backward tumble and roll.
	local variation = Vector3.new((math.random(0, 1) == 0 and -1 or 1) * math.random(80, 120) / 100,
		math.random(-80, 80) / 100, math.random(-20, 20) / 100)
	if owner then
		-- The grappler remains the simulator of a tethered victim.
		Remotes.ApplyFlop:FireClient(owner, character, direction, workspace:GetServerTimeNow(), variation)
	else
		Motion.Apply(character, direction, nil, variation)
	end
end)
Players.PlayerRemoving:Connect(function(player) lastRequest[player] = nil end)

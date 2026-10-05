-- Persistent across respawns. Physics state enforcement is shared with the
-- grappler/observers through RagdollService; only this client's controls lock.
local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
require(Storage.Modules:WaitForChild("RagdollService")).InitClient()

local controls
local character, humanoid
local connections = {}
local latestSession, remoteLocked = 0, false
local disabledByGrapple = false
local controlsWereEnabled = true

local function update()
	local locked = humanoid ~= nil and humanoid.Health > 0
		and (remoteLocked or humanoid:GetAttribute("GrapplePhysicsLocked") == true)
	if humanoid then
		-- Client-only marker also covers a RemoteEvent arriving ahead of attributes.
		humanoid:SetAttribute("GrappleLocalPhysicsLock", locked or nil)
		if locked then
			humanoid.Jump = false
			humanoid:Move(Vector3.zero, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end
	if not controls then return end
	if locked and not disabledByGrapple then
		controlsWereEnabled = controls.controlsEnabled ~= false
		disabledByGrapple = true
		controls:Disable()
	elseif not locked and disabledByGrapple then
		disabledByGrapple = false
		if controlsWereEnabled then controls:Enable() end
	end
end

local function clearCharacter()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	if humanoid then humanoid:SetAttribute("GrappleLocalPhysicsLock", nil) end
	character, humanoid, remoteLocked, latestSession = nil, nil, false, 0
	update()
end

local function bindCharacter(nextCharacter)
	clearCharacter()
	character = nextCharacter
	local nextHumanoid = nextCharacter:WaitForChild("Humanoid", 10)
	if character ~= nextCharacter or player.Character ~= nextCharacter or not nextHumanoid then return end
	humanoid = nextHumanoid
	table.insert(connections, humanoid:GetAttributeChangedSignal("GrapplePhysicsLocked"):Connect(update))
	table.insert(connections, humanoid.Died:Connect(function()
		remoteLocked = false
		update()
	end))
	update()
end

-- Connect before waiting for PlayerModule, so its initialization cannot drop a lock.
Remotes.GrappleVictimState.OnClientEvent:Connect(function(targetCharacter, session, locked)
	if targetCharacter ~= player.Character or targetCharacter ~= character then return end
	if typeof(session) ~= "number" or session < latestSession then return end
	-- A duplicate start for a completed session must not lock controls again.
	if session == latestSession and not remoteLocked and locked then return end
	latestSession, remoteLocked = session, locked == true
	update()
end)
player.CharacterRemoving:Connect(function(oldCharacter)
	if character == oldCharacter then clearCharacter() end
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.spawn(bindCharacter, player.Character) end

controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
update()

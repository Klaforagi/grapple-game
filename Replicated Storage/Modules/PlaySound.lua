-- Sounds module so that you won't have to copy paste the same sounds
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- You can change this to wherever your global sounds are stored
local DefaultSoundLibrary = ReplicatedStorage:WaitForChild("Sounds")

local function PlaySound(source: Instance?, soundInput: string | Sound)
	-- Fallback source
	source = source or workspace

	-- Get the sound instance
	local sound: Sound? = nil

	if typeof(soundInput) == "Instance" and soundInput:IsA("Sound") then
		sound = soundInput
	elseif typeof(soundInput) == "string" then
		-- Try to find by name in sound library
		local found = DefaultSoundLibrary:FindFirstChild(soundInput,true)
		if found and found:IsA("Sound") then
			sound = found
		end
	end

	if not sound then
		warn("[PlaySound] Sound not found or invalid:", soundInput)
		return
	end

	-- Play cloned version
	local clone = sound:Clone()
	clone.Parent = source
	clone:Play()
	Debris:AddItem(clone, clone.TimeLength + 0.1)
end

return PlaySound

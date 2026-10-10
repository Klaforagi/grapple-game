local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local MusicVolume = {}
local sounds = {}
local volume = 1
local ready = false

local function apply(sound, record)
	sound.Volume = ready and math.clamp(record.base * volume, 0, 10) or 0
	if ready and record.resume then
		record.resume = false
		sound:Resume()
	elseif not ready and sound.Playing then
		record.resume = true
		sound:Pause()
	end
end

local function track(sound)
	if not sound:IsA("Sound") or sounds[sound] then return end
	local record = {base = sound.Volume, resume = false}
	sounds[sound] = record
	record.connection = sound:GetPropertyChangedSignal("Playing"):Connect(function()
		if not ready then apply(sound, record) end
	end)
	sound.Destroying:Once(function()
		record.connection:Disconnect()
		sounds[sound] = nil
	end)
	apply(sound, record)
end

function MusicVolume.SetVolume(value)
	volume = math.clamp(value, 0, 1)
	for sound, record in pairs(sounds) do apply(sound, record) end
end

local function settingsChanged()
	local saved = player:GetAttribute("MusicVolume")
	-- Wait for both the completion flag and the replicated volume value.
	ready = player:GetAttribute("SettingsLoaded") == true and typeof(saved) == "number"
	MusicVolume.SetVolume(typeof(saved) == "number" and saved or 1)
end
player:GetAttributeChangedSignal("SettingsLoaded"):Connect(settingsChanged)
player:GetAttributeChangedSignal("MusicVolume"):Connect(settingsChanged)
settingsChanged()

local function folderAdded(folder)
	if folder.Name ~= "Music" then return end
	folder.DescendantAdded:Connect(track)
	for _, sound in ipairs(folder:GetDescendants()) do track(sound) end
end
Storage.ChildAdded:Connect(folderAdded)
for _, folder in ipairs(Storage:GetChildren()) do folderAdded(folder) end

return MusicVolume

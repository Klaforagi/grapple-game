-- Multiplies every Sound except the music library. SoundGroup.Volume scales
-- character jumps and footsteps, workspace part sounds, and UI sounds without
-- rewriting each Sound.Volume, so scripts can still set their own loudness.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer

local EffectsVolume = {}
local group = SoundService:FindFirstChild("Effects")
if not (group and group:IsA("SoundGroup")) then
	group = Instance.new("SoundGroup")
	group.Name = "Effects"
	group.Parent = SoundService
end
group.Volume = 1

local claimed = {}

local function isMusic(sound)
	local current = sound.Parent
	while current and current ~= game do
		if current.Name == "Music" and current:IsA("Folder") then return true end
		current = current.Parent
	end
	return false
end

local function claim(sound)
	if not sound:IsA("Sound") or claimed[sound] or isMusic(sound) then return end
	claimed[sound] = true
	local function assign()
		if not sound.Parent or isMusic(sound) then return end
		if sound.SoundGroup ~= group then sound.SoundGroup = group end
	end
	assign()
	sound:GetPropertyChangedSignal("SoundGroup"):Connect(assign)
	sound.Destroying:Once(function() claimed[sound] = nil end)
end

local function watch(root)
	if not root then return end
	root.DescendantAdded:Connect(claim)
	for _, instance in ipairs(root:GetDescendants()) do claim(instance) end
end

watch(workspace)
watch(SoundService)
watch(game:GetService("Lighting"))
watch(game:GetService("ReplicatedStorage"))
task.spawn(function()
	watch(player:WaitForChild("PlayerGui"))
end)
if player:FindFirstChild("PlayerScripts") then
	watch(player.PlayerScripts)
else
	player.ChildAdded:Connect(function(child)
		if child.Name == "PlayerScripts" then watch(child) end
	end)
end

function EffectsVolume.SetVolume(value)
	group.Volume = math.clamp(value, 0, 1)
end

local function settingsChanged()
	local saved = player:GetAttribute("EffectsVolume")
	local ready = player:GetAttribute("SettingsLoaded") == true and typeof(saved) == "number"
	-- Stay silent until the saved slider arrives, matching the music gate.
	EffectsVolume.SetVolume(ready and saved or 0)
end
player:GetAttributeChangedSignal("SettingsLoaded"):Connect(settingsChanged)
player:GetAttributeChangedSignal("EffectsVolume"):Connect(settingsChanged)
settingsChanged()

return EffectsVolume

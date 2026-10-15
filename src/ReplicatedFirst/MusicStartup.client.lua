-- Start the playback gates before the HUD/character scripts initialize.
local storage = game:GetService("ReplicatedStorage")
require(storage:WaitForChild("Modules"):WaitForChild("MusicVolume"))
require(storage:WaitForChild("Modules"):WaitForChild("EffectsVolume"))

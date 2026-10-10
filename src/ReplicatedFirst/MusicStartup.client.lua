-- Start the playback gate before the HUD/character scripts initialize.
local storage = game:GetService("ReplicatedStorage")
require(storage:WaitForChild("Modules"):WaitForChild("MusicVolume"))

-- One persistent controller across respawns; no StarterGui assets required.
local storage = game:GetService("ReplicatedStorage")
require(storage.Modules:WaitForChild("GrappleHud")).Init()

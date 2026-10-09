local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local Motion = require(Storage.Modules:WaitForChild("FlopMotion"))
Remotes.ApplyFlop.OnClientEvent:Connect(function(character, direction, sentAt, variation)
	if workspace:GetServerTimeNow() - sentAt > 0.5 then return end
	if character and character:IsDescendantOf(workspace) then
		Motion.Apply(character, direction, Players.LocalPlayer, variation)
	end
end)

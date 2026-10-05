-- Server creates the protocol; clients never depend on Studio-authored remotes.
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")
local names = {"FireGrapple", "ChangeLength", "ToggleWallMode", "ToggleRagdoll", "ResetCharacter", "GrappledPlayer", "GrappledWall", "HasBeenGrappled", "GrappleVictimState", "StruggleInput", "StruggleProgress", "ThrowBomb"}
local folder
if RunService:IsServer() then
	folder = storage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = storage
	end
	for _, name in ipairs(names) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = storage:WaitForChild("Remotes")
end
local remotes = {}
for _, name in ipairs(names) do remotes[name] = folder:WaitForChild(name) end
return remotes

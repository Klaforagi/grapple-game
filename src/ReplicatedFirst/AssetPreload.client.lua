-- Begin downloading UI images, sounds, textures, and Push clips as soon as they replicate.
local storage = game:GetService("ReplicatedStorage")
require(storage:WaitForChild("Modules"):WaitForChild("GameAssetPreload")).Start()

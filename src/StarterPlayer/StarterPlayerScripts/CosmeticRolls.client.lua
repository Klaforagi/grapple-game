local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage.Modules:WaitForChild("GameAssetPreload")).Wait(8)
require(ReplicatedStorage.Modules:WaitForChild("CosmeticRollUi")).Init()

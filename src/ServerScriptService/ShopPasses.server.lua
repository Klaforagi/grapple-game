-- Temporary. The shop buy button toggles these on and off so passes can be
-- tested before their Robux prompts exist. Remove this with ToggleTestPass.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Modules:WaitForChild("GrappleRemotes"))
local Catalog = require(ReplicatedStorage.Modules:WaitForChild("ShopCatalog"))

local allowed = {}
for _, pass in ipairs(Catalog.Passes) do
	allowed[pass.name] = true
end

Remotes.ToggleTestPass.OnServerEvent:Connect(function(player, name)
	if type(name) ~= "string" or not allowed[name] then return end
	local key = Catalog.TestAttribute(name)
	player:SetAttribute(key, player:GetAttribute(key) ~= true)
end)

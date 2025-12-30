local plr = game.Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Indicators = script.Parent
	
----------------------------------------------------------------
-- This is already self explanatory so I did not add comments 
----------------------------------------------------------------
	
Remotes.GrappledPlayer.OnClientEvent:Connect(function(victim)
	if victim then
		
		Indicators.GrapplingPlayer.Text = "Grappling "..victim.Name
		
	end
	Indicators.GrapplingPlayer.Visible = victim and true or false
end)

Remotes.HasBeenGrappled.OnClientEvent:Connect(function(player)
	if player then
		
		Indicators.GrappledBy.Text = "Grappled by "..player.Name
		
	end
	Indicators.GrappledBy.Visible = player and true or false
end)

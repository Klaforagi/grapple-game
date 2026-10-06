local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ServerRestartNotice", false, 100
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 20)
banner.Size = UDim2.fromOffset(520, 60)
banner.BackgroundColor3 = Color3.fromRGB(104, 50, 42)
banner.BackgroundTransparency = 0.08
banner.BorderSizePixel = 0
banner.Font = Enum.Font.GothamBold
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextSize = 16
banner.TextWrapped = true
banner.Visible = false
banner.Parent = gui
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 10)

Remotes.ServerRestartNotice.OnClientEvent:Connect(function(message, restartUnix)
	banner.Text = tostring(message)
	banner.Visible = true
end)

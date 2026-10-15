local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Remotes = require(Storage.Modules:WaitForChild("GrappleRemotes"))
local Style = require(Storage.Modules:WaitForChild("CosmeticStyle"))

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ServerRestartNotice", false, 100
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 20)
banner.Size = UDim2.fromOffset(520, 60)
banner.Visible = false
banner.Parent = gui
Style.Surface(banner, Color3.fromRGB(150, 64, 72), 8)

local message = Instance.new("TextLabel")
message.BackgroundTransparency = 1
message.Size = UDim2.fromScale(1, 1)
message.Font = Enum.Font.GothamBold
message.TextColor3 = Style.Text
message.TextStrokeColor3 = Style.Ink
message.TextStrokeTransparency = 0.45
message.TextSize = 16
message.TextWrapped = true
message.Parent = banner

Remotes.ServerRestartNotice.OnClientEvent:Connect(function(text)
	message.Text = tostring(text)
	banner.Visible = true
end)

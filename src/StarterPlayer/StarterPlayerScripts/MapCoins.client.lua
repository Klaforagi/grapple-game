-- Hides a grass coin the moment the local player runs over it. The Coin sound
-- and the +amount popup play in that same moment. Coins spin slowly on this client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PlaySound = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlaySound"))
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectMapCoin")
local Remotes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrappleRemotes"))

local PAD = Vector3.new(2.5, 4, 2.5)
local SPIN = math.pi * 2 / 6
local pending = {}
local celebrated = {}

local function eachVisible(model, apply)
	if model:IsA("BasePart") or model:IsA("Decal") or model:IsA("Texture") then apply(model) end
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then apply(item) end
	end
end

local function hide(model)
	eachVisible(model, function(item)
		item.LocalTransparencyModifier = 1
	end)
end

local function show(model)
	if not model or not model.Parent then return end
	eachVisible(model, function(item)
		item.LocalTransparencyModifier = 0
	end)
end

local function pointHits(cf, half, point)
	local localPoint = cf:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function overlaps(fromPos, toPos, model)
	local cf, size = model:GetBoundingBox()
	if not cf or not size then return false end
	local half = size * 0.5 + PAD
	if pointHits(cf, half, toPos) or pointHits(cf, half, fromPos) then return true end
	local travel = toPos - fromPos
	if travel.Magnitude <= 4 then return false end
	return pointHits(cf, half, fromPos + travel * 0.5)
end

local popping = 0
local function showGain(amount)
	local gui = player:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("GrappleHUD")
	local coins = hud and hud:FindFirstChild("Coins")
	local amountLabel = coins and coins:FindFirstChild("Amount")
	if not coins or not amountLabel then return end
	local popup = Instance.new("TextLabel")
	popup.Name = "CoinGain"
	popup.BackgroundTransparency = 1
	popup.Font = amountLabel.Font
	-- The chip draws its amount at the fitted pixel size. This popup stays at the authored 20.
	popup.TextSize = 20
	popup.TextColor3 = amountLabel.TextColor3
	popup.TextXAlignment = Enum.TextXAlignment.Left
	popup.Text = "+" .. tostring(amount)
	popup.AnchorPoint = Vector2.new(0, 0.5)
	-- Parent is the HUD, not the coin chip. The chip's list would pin this to the left side.
	local topLeft = coins.AbsolutePosition - hud.AbsolutePosition
	local originX = topLeft.X + coins.AbsoluteSize.X + 8
	local originY = topLeft.Y + math.max(coins.AbsoluteSize.Y * 0.5, 16) - (popping % 4) * 16
	popup.Position = UDim2.fromOffset(originX, originY)
	popup.Size = UDim2.fromOffset(72, 28)
	popup.ZIndex = 8
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = popup
	local scale = Instance.new("UIScale")
	scale.Scale = 0.35
	scale.Parent = popup
	popup.Parent = hud
	popping += 1
	local grow = TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	local rise = TweenService:Create(popup, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(originX, originY - 26),
		TextTransparency = 1,
	})
	local fadeStroke = TweenService:Create(stroke, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	})
	grow:Play()
	task.delay(0.16, function()
		if not popup.Parent then
			popping = math.max(0, popping - 1)
			return
		end
		rise:Play()
		fadeStroke:Play()
	end)
	rise.Completed:Connect(function()
		popping = math.max(0, popping - 1)
		popup:Destroy()
	end)
end

local function pickupAmount()
	local amount = player:GetAttribute("MapCoinPayout")
	if type(amount) ~= "number" or amount < 1 then return 1 end
	return math.floor(amount)
end

local function celebrate(amount)
	PlaySound(SoundService, "Coin")
	showGain(amount)
end

Remotes.CoinGain.OnClientEvent:Connect(function(amount)
	if type(amount) == "number" and amount > 0 then celebrate(amount) end
end)

remote.OnClientEvent:Connect(function(model, amount)
	if model then pending[model] = nil end
	if type(amount) == "number" and amount > 0 then
		if not model or not celebrated[model] then
			if model then hide(model) end
			celebrate(amount)
		end
	else
		show(model)
	end
	if model then celebrated[model] = nil end
end)

local lastPosition
RunService.Heartbeat:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		lastPosition = nil
		return
	end
	local position = root.Position
	local previous = lastPosition or position
	lastPosition = position
	local folder = Workspace:FindFirstChild("MapCoins")
	if not folder then return end
	for _, model in ipairs(folder:GetChildren()) do
		if not pending[model] and model.Parent and overlaps(previous, position, model) then
			pending[model] = true
			celebrated[model] = true
			hide(model)
			celebrate(pickupAmount())
			remote:FireServer(model)
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local folder = Workspace:FindFirstChild("MapCoins")
	if not folder or not dt then return end
	local turn = CFrame.Angles(0, SPIN * dt, 0)
	for _, model in ipairs(folder:GetChildren()) do
		if model.Parent and model.GetPivot and model.PivotTo then
			model:PivotTo(model:GetPivot() * turn)
		end
	end
end)

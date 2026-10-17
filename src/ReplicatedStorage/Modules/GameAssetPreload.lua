-- Client-side startup cache for the static UI and gameplay assets.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterPack = game:GetService("StarterPack")

local Assets = require(ReplicatedStorage:WaitForChild("Assets"))
local Config = require(ReplicatedStorage:WaitForChild("GrappleConfig"))
local Shop = require(script.Parent:WaitForChild("ShopCatalog"))

local Preload = {}
local started, uiFinished = false, false

local function collect()
	local images, other, temporary, seen = {}, {}, {}, {}
	local function add(className, property, id)
		if type(id) ~= "string" or id == "" or seen[id] then return end
		seen[id] = true
		local asset = Instance.new(className)
		asset[property] = id
		table.insert(temporary, asset)
		table.insert(className == "ImageLabel" and images or other, asset)
	end
	for _, id in pairs(Assets) do add("ImageLabel", "Image", id) end
	for _, pass in ipairs(Shop.Passes) do add("ImageLabel", "Image", pass.image) end
	for _, pack in ipairs(Shop.Coins) do add("ImageLabel", "Image", pack.image) end
	for _, id in ipairs({
		Config.toolIcon, Config.bombToolIcon, Config.pushToolIcon,
		Config.CustomCursorIcon, Config.GrappleInUseIcon, Config.MouseObstructedIcon,
		"rbxassetid://253828517", -- music button
		"rbxassetid://118784136329728", -- daily rewards
		"rbxassetid://5012125430", -- day
		"rbxassetid://5012126105", -- night
	}) do add("ImageLabel", "Image", id) end
	add("Animation", "AnimationId", Config.pushAnimationId)
	add("Animation", "AnimationId", Config.pushAnimationR15Id)
	add("Beam", "Texture", "rbxassetid://18383765441") -- Chain rope
	local function addContainer(container)
		if container then table.insert(other, container) end
	end
	addContainer(ReplicatedStorage:WaitForChild("Sounds", 2))
	addContainer(ReplicatedStorage:WaitForChild("Templates", 2))
	addContainer(SoundService)
	addContainer(StarterPack)
	return images, other, temporary
end

function Preload.Start()
	if started then return end
	started = true
	task.spawn(function()
		local temporary = {}
		local ok, err = pcall(function()
			local images, other
			images, other, temporary = collect()
			-- UI is the first thing players interact with. Do not let sounds or
			-- tool assets delay its icons.
			ContentProvider:PreloadAsync(images)
			uiFinished = true
			ContentProvider:PreloadAsync(other)
		end)
		if not ok then warn("[Assets] Startup preload failed:", err) end
		for _, instance in ipairs(temporary) do instance:Destroy() end
		uiFinished = true
	end)
end

function Preload.Wait(maxSeconds)
	Preload.Start()
	local deadline = os.clock() + (maxSeconds or 8)
	while not uiFinished and os.clock() < deadline do task.wait(0.05) end
	return uiFinished
end

return Preload

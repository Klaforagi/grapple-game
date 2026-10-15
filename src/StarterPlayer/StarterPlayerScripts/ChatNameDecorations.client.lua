-- Keep Roblox's built-in chat UI intact; only decorate each sender's prefix.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Palettes = require(ReplicatedStorage:WaitForChild("ItemColors"))

local function escape(text)
	return string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
end

local function span(text, color)
	return string.format('<font color="rgb(%d,%d,%d)">%s</font>',
		math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255), escape(text))
end

local function gradientText(value, stops)
	local letters = utf8.len(value) or #value
	if letters <= 1 then return span(value, stops[1]) end
	local output, index = {}, 0
	for _, codepoint in utf8.codes(value) do
		index += 1
		local phase = (index - 1) / (letters - 1)
		local scaled = phase * (#stops - 1)
		local left = math.floor(scaled) + 1
		local color = stops[left]:Lerp(stops[math.min(left + 1, #stops)], scaled - math.floor(scaled))
		table.insert(output, span(utf8.char(codepoint), color))
	end
	return table.concat(output)
end

TextChatService.OnIncomingMessage = function(message)
	local source = message.TextSource
	local player = source and Players:GetPlayerByUserId(source.UserId)
	if not player then return end

	local properties = Instance.new("TextChatMessageProperties")
	local name = player.DisplayName .. ":"
	local ropeName = player:GetAttribute("GrappleRopeColor")
	if ropeName == "Rainbow" then
		name = gradientText(name, Palettes.RainbowStops)
	elseif ropeName == "Gold" then
		name = gradientText(name, Palettes.GoldStops)
	else
		name = span(name, Palettes.Rope[ropeName] or Palettes.Rope.Gray)
	end

	local vip = player:GetAttribute("TestPass_VIP") == true and gradientText("[VIP] ", Palettes.GoldStops) or ""
	properties.PrefixText = vip .. name
	return properties
end

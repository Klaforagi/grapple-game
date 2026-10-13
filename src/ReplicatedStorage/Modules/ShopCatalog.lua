-- ids stay 0 until the gamepass or developer product exists on the Roblox dashboard.
-- A 0 id still shows its price and does not open a purchase prompt.
-- price is only the label on the button. The prompt charges whatever the dashboard says.
-- image stays empty until art is ready. A coin pack with no image falls back to the coin icon.
return {
	Passes = {
		{
			id = 0,
			name = "VIP",
			description = "Stand out with a VIP tag.",
			price = 399,
			color = Color3.fromRGB(255, 186, 64),
			image = "rbxassetid://90868525428150",
		},
		{
			id = 0,
			name = "2x Coins",
			description = "Earn coins twice as fast.",
			price = 249,
			color = Color3.fromRGB(64, 196, 120),
			image = "rbxassetid://106709097415594",
		},
		{
			id = 0,
			name = "2x Luck",
			description = "Twice the luck.",
			price = 199,
			color = Color3.fromRGB(164, 112, 232),
			image = "rbxassetid://104262459603842",
		},
		-- key is the future ownership check. These passes do not gate the tools yet.
		{
			id = 0,
			key = "Push",
			name = "Push",
			description = "Shove players in front of you.",
			price = 179,
			color = Color3.fromRGB(255, 112, 84),
			image = "rbxassetid://130453582263275",
		},
		{
			id = 0,
			key = "WallMode",
			name = "Wall Mode",
			description = "Tether onto walls and objects.",
			price = 349,
			color = Color3.fromRGB(88, 168, 232),
			image = "rbxassetid://113241743229029",
		},
	},
	Coins = {
		{id = 0, amount = 100, price = 49, image = "rbxassetid://112879496061308"},
		{id = 0, amount = 500, price = 149, image = "rbxassetid://134980103199674"},
		{id = 0, amount = 1500, price = 349, image = "rbxassetid://111618971053629"},
		{id = 0, amount = 4000, price = 799, image = "rbxassetid://96102087038616"},
	},
}

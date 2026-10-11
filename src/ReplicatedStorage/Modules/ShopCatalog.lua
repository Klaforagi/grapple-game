-- ids stay 0 until the gamepass or developer product exists on the Roblox dashboard.
-- A 0 id still shows its price and does not open a purchase prompt.
-- price is only the label on the button. The prompt charges whatever the dashboard says.
-- image stays empty until art is ready. Coin packs fall back to the coin icon.
return {
	Passes = {
		{
			id = 0,
			name = "VIP",
			description = "Stand out with a VIP tag.",
			price = 399,
			color = Color3.fromRGB(255, 186, 64),
			image = "",
		},
		{
			id = 0,
			name = "2x Coins",
			description = "Earn coins twice as fast.",
			price = 249,
			color = Color3.fromRGB(64, 196, 120),
			image = "",
		},
		{
			id = 0,
			name = "2x Luck",
			description = "Twice the luck.",
			price = 199,
			color = Color3.fromRGB(164, 112, 232),
			image = "",
		},
	},
	Coins = {
		{id = 0, amount = 100, price = 49, image = ""},
		{id = 0, amount = 500, price = 149, image = ""},
		{id = 0, amount = 1500, price = 349, image = ""},
		{id = 0, amount = 4000, price = 799, image = ""},
	},
}

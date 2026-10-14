# Cosmetic rolls

## Studio setup

Create your station model anywhere under `Workspace` and name it **`CosmeticRollStation`**. Inside it, put one anchored `Part` named **`RollZone`** at the place where players should stand. The part can be invisible (`Transparency = 1`, `CanCollide = false`); touch events and `CanTouch` are not required. Keep the model's scenery anchored. With streaming enabled, set the model's `ModelStreamingMode` to `Atomic` so its complete shape arrives together.

The UI opens within 10 studs of the zone's surface, including when standing inside it. The server permits a 14-stud distance to allow for replication delay. The collection billboard appears within 45 studs and sits above the model. These distances and names live in `src/ReplicatedStorage/Modules/CosmeticCatalog.lua`. Closing the panel keeps it closed until the player leaves and approaches again. Multiple station models are supported.

No GUI, prompt, script, or billboard needs to be placed inside your model. Rojo sync installs the code; the map model remains yours to create in Studio.

## Collection and rarity

Every player starts with Gun / Black, Rope / Gray, and Bomb / Cyan. These are Common and count toward completion, but never enter the roll pool. Existing players also start from these three unless they have saved roll unlocks; old equipped choices are not unlocks. There are currently **42 collectible cosmetics: 3 starters and 39 rollable items**. Gold and admin Banana are excluded from collection totals.

| Rarity | Items | Independent check | Current overall chance | Duplicate refund |
| --- | --- | --- | --- | --- |
| Legendary | Rainbow for Gun, Rope, Bomb | 0.1% | 0.1% | 100 coins |
| Epic | None yet | 1% | 0% until populated | 75 coins |
| Rare | None yet | 10% | 0% until populated | 50 coins |
| Uncommon | Gun/Rope: Teal, Lime, Pink; Bomb: Mint, Pink | 35% | 34.965% | 25 coins |
| Common | All other available colors, excluding starters | Fallback | 64.935% | 10 coins |

A roll costs **100 coins**. Check the highest populated rarity first and stop at the first successful independent check. Skip empty tiers. If every check fails, choose Common. Then pick uniformly from **all items in the winning rarity**, combining Gun, Rope, and Bomb; category is not a separate roll. Owned items remain eligible. Duplicate refunds change held coins only, never lifetime coins or the leaderboard. Even a Legendary duplicate requires the full 100-coin balance before its 100-coin refund.

Currently, each Rainbow is approximately 0.033333% per roll, each of the 8 Uncommons is 4.370625%, and each of the 28 rollable Commons is approximately 2.319107%. With every tier populated, the overall chances would be Legendary 0.1%, Epic 0.999%, Rare 9.8901%, Uncommon 31.153815%, Common 57.857085%. The UI calculates these probabilities from the actual populated pools and displays individual odds rounded to four decimal places.

Gold remains in the equipment palettes for a future VIP implementation but is absent from rolls, ordinary inventory, and the codex. Banana appears only in admins' Bomb inventory, using `ServerScriptService/AdminList.lua`; the server rejects non-admin Banana equips.

## Adding items

Add a new color to the relevant palette in `src/ReplicatedStorage/ItemColors.lua`, including its swatch if the displayed color should differ from the equipment color. It enters the catalog as Common automatically. Assign another rarity in the per-category `overrides` table in `CosmeticCatalog.lua`. The codex, inventory, odds list, roll pool, and collection denominator update from that shared catalog. Use stable category/color names: the saved identifier is `Kind_Name`, such as `Gun_Rainbow`. Renaming an existing item requires a saved-data migration.

Future model-based skins also need equipment rendering support; adding a catalog entry alone does not create a new 3D model. Rainbow already uses the existing animated equipment renderer.

## Saving and availability

`GrappleCoins_v1` stores rolled ownership in `cosmetics` alongside the coin balance. The charge, unlock, duplicate refund, and last-roll receipt commit together in one `UpdateAsync`. A failed response retains its request ID in the current session so retrying can recover that result without charging again. Committed rewards survive leaving during the animation. Cosmetic equip choices and personal settings remain in `GrappleCosmetics_v1`; loading never overwrites saved data after a failed read.

The server chooses outcomes, validates location and character state, rejects concurrent requests, and applies a five-second cooldown. Clients cannot choose an outcome, refund, or price. Inventory selection is checked against server-owned collection attributes.

Coins can be purchased in the existing shop, so the roll server checks `PolicyService:GetPolicyInfoForPlayerAsync`. Restricted accounts cannot roll, and availability failures retry with rolling disabled. Both exact outcome listings and numerical odds are accessible before purchase, following [Roblox's paid random item requirements](https://create.roblox.com/docs/production/monetization/paid-random-items).

## Validation

Run `tests/run.ps1 -LuauPath <path-to-luau.exe>` for the existing regression suite plus catalog, odds boundaries, unlock/refund persistence, ambiguous-save recovery, and station validation tests. These mocks do not render Roblox UI.

In a published Studio test place with DataStore access, place the named station and use the admin coin grant to fund a test account. Verify the initial `Owned 3 out of 42`, auto-open and close/reapproach behavior, reel landing, new-item count changes, duplicate refunds, and equip/rejoin persistence. Repeat on phone and desktop emulation and with two players to confirm that each billboard shows its viewer's collection. Verify Banana with an admin and a non-admin. Use a test place so testing does not change live coin/collection data.

# Cosmetic rolls

## Studio setup

Create your station model anywhere under `Workspace` and name it **`CosmeticRollStation`**. Inside it, put one anchored `Part` named **`RollZone`** at the place where players should stand. The part can be invisible (`Transparency = 1`, `CanCollide = false`); touch events and `CanTouch` are not required. Keep the model's scenery anchored. With streaming enabled, set the model's `ModelStreamingMode` to `Atomic` so its complete shape arrives together.

The UI opens within 10 studs of the zone's surface, including when standing inside it. The server permits a 14-stud distance to allow for replication delay. The collection billboard appears within 45 studs and sits above the model. These distances and names live in `src/ReplicatedStorage/Modules/CosmeticCatalog.lua`. Closing the panel keeps it closed until the player leaves and approaches again. Multiple station models are supported.

No GUI, prompt, script, or billboard needs to be placed inside your model. Rojo sync installs the code; the map model remains yours to create in Studio.

The station is labeled **COSMETICS**. Its dark gradient panels share their style with the inventory. Opening it closes other game windows, temporarily hides other screen GUIs and the native hotbar, and restores normal HUD visibility on close. There is no fullscreen tint or pointer-blocking backdrop, so camera dragging remains available. Inventory also hides the hotbar while open and has All / Gun / Rope / Bomb tabs, a scrollable item grid, and a selected-item equip preview.

Opening inventory closes Shop, Upgrades, Settings, Codex, Admin, and the menu dropdown in the same button handler. Its `Owned X out of X` counter follows the active tab; All shows the complete collection, while Gun, Rope, and Bomb count only that category. Copies and admin-only Banana do not inflate completion. Bomb artwork in the inventory and reel is a glowing sphere with no fuse. The roll status reads `Rolling...` until the result appears.

The idle reel continuously drifts left, cycling through a shuffled list of all rollable cosmetics. It keeps seven preview cards alive, replacing cards after they leave the screen. Idle previews do not indicate drop frequencies and are silent. The center pointer appears for an actual roll; the result stays visible for four seconds before the idle preview resumes. Bomb icons have no shine marks or shadow bar. Button text sits above the decorative gradient so selected tabs stay bright.

Place a `Sound` named **`Tick`** under `ReplicatedStorage/Sounds` (nested folders work too). The client clones it locally as each item center passes the reel pointer. The timing follows reel movement, including deceleration, rather than a fixed timer. Other players do not hear these ticks.

## Collection and rarity

Every player starts with Gun / Black, Rope / Gray, and Bomb / Cyan. These are Common and count toward completion, but never enter the roll pool. Existing players also start from these three unless they have saved roll unlocks; old equipped choices are not unlocks. There are currently **42 collectible cosmetics: 3 starters and 39 rollable items**. Gold and admin Banana are excluded from collection totals.

| Rarity | Items | Independent check | Current overall chance |
| --- | --- | --- | --- |
| Legendary | Rainbow for Gun, Rope, Bomb | 0.5% | 0.5% |
| Epic | None yet | 1% | 0% until populated |
| Rare | None yet | 10% | 0% until populated |
| Uncommon | Gun/Rope: Teal, Lime, Pink; Bomb: Mint, Pink | 35% | 34.825% |
| Common | All other available colors, excluding starters | Fallback | 64.675% |

A roll costs **100 coins**. Check the highest populated rarity first and stop at the first successful independent check. Skip empty tiers. If every check fails, choose Common. Then pick uniformly from **all items in the winning rarity**, combining Gun, Rope, and Bomb; category is not a separate roll. Owned items remain eligible. Every duplicate adds one extra copy; there are no automatic coin refunds. Inventory icons show `x2`, `x3`, etc. in their bottom corner, with no quantity badge for one copy. The codex and billboard still count unique collected items, not copies. The starter colors stay at one copy and are excluded from rolling.

Currently, each Rainbow is approximately 0.166667% per roll, each of the 8 Uncommons is 4.353125%, and each of the 28 rollable Commons is approximately 2.309821%. With every tier populated, the overall chances would be Legendary 0.5%, Epic 0.995%, Rare 9.8505%, Uncommon 31.029075%, Common 57.625425%. The UI calculates these probabilities from the actual populated pools and displays individual odds rounded to four decimal places. The odds panel contains only the rarity totals and possible items; algorithm explanations are kept in this document.

Gold remains in the equipment palettes for a future VIP implementation but is absent from rolls, ordinary inventory, and the codex. Banana appears only in admins' Bomb inventory, using `ServerScriptService/AdminList.lua`; the server rejects non-admin Banana equips.

## Selling

Select an item in inventory and click **SELL**, then **CONFIRM** to sell one copy. The displayed sale price is Common **10**, Uncommon **25**, Rare **100**, Epic **200**, Legendary **500** coins, configured in `CosmeticCatalog.SellPrices`. Choosing a different item/tab, equipping, closing inventory, or receiving an ownership update cancels an unsubmitted confirmation. An interrupted sale offers **RETRY** for the same transaction, with selection locked until it is resolved.

Starters and admin Banana have no Sell button and are rejected by the server. Selling a spare keeps the skin equipped; selling the last copy automatically equips that category's starter. The coin credit and copy removal save atomically in `GrappleCoins_v1`. Proceeds affect held coins only, not lifetime earnings. Retrying a receipt cannot remove or credit another copy. Collection counts represent items currently owned and decrease when the last copy is sold.

## Adding items

Add a new color to the relevant palette in `src/ReplicatedStorage/ItemColors.lua`, including its swatch if the displayed color should differ from the equipment color. It enters the catalog as Common automatically. Assign another rarity in the per-category `overrides` table in `CosmeticCatalog.lua`. The codex, inventory, odds list, roll pool, and collection denominator update from that shared catalog. Use stable category/color names: the saved identifier is `Kind_Name`, such as `Gun_Rainbow`. Renaming an existing item requires a saved-data migration.

Future model-based skins also need equipment rendering support; adding a catalog entry alone does not create a new 3D model. Rainbow already uses the existing animated equipment renderer.

## Saving and availability

`GrappleCoins_v1` stores rolled quantities in `cosmetics` alongside the coin balance. Existing boolean `true` entries are treated as one copy, and their next roll writes the new numeric count. The charge, added copy, and last-roll receipt commit together in one `UpdateAsync`. A failed response retains its request ID in the current session so retrying recovers that result without charging or adding a copy twice. Committed rewards survive leaving during the animation. Cosmetic equip choices and personal settings remain in `GrappleCosmetics_v1`; loading never overwrites saved data after a failed read.

The server chooses outcomes, validates location and character state, rejects concurrent requests, and applies a five-second cooldown. Clients cannot choose an outcome, quantity, or price. Inventory selection is checked against server-owned collection attributes.

Coins can be purchased in the existing shop, so the roll server checks `PolicyService:GetPolicyInfoForPlayerAsync`. Restricted accounts cannot roll, and availability failures retry with rolling disabled. Both exact outcome listings and numerical odds are accessible before purchase, following [Roblox's paid random item requirements](https://create.roblox.com/docs/production/monetization/paid-random-items).

## Validation

Run `tests/run.ps1 -LuauPath <path-to-luau.exe>` for the existing regression suite plus catalog, odds boundaries, stack persistence and migration, atomic sales and retry recovery, station validation, and UI visibility restoration tests. These mocks do not render Roblox UI or play audio.

In a published Studio test place with DataStore access, place the named station and use the admin coin grant to fund a test account. Verify the initial `Owned 3 out of 42`, auto-open and close/reapproach behavior, reel landing and tick timing, new-item count changes, duplicate stacks, and equip/rejoin persistence. Open inventory/shop/settings before approaching: they should close and stay closed after exiting. Check hotbar restoration, camera dragging outside controls, all four inventory tabs, and quantity badges. Repeat on phone and desktop emulation and with two players to confirm local-only ticks and per-viewer collection counts. Verify Banana with an admin and a non-admin. Use a test place so testing does not change live coin/collection data.

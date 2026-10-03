# LootLog - Running List

Last updated: October 3, 2026 (Hunting Log added)

How to use: keep this file in your LootLog project folder (the .toc ignores it).
Tick boxes yourself in VS Code as things get done. I can't see your local copy,
so when you want it refreshed, tell me what changed and I'll regenerate it.

---

## Done

- [x] Loot capture from the loot window, works with auto loot (`Capture.lua`)
- [x] Per-mob kills, item quantity, drop count, and drop rate
- [x] Item IDs, item links, and icons stored
- [x] Duplicate guards (reopening a corpse, LOOT_OPENED + LOOT_READY both firing)
- [x] Kills counted for corpses that dropped only coin (keeps drop rates honest)
- [x] Main window with left menu and an on-screen open button (`UI.lua`)
- [x] Mob Drops page: mob list, drops table, hover tooltips (`PageMobs.lua`)
- [x] Fishing log grouped by zone (text page)
- [x] Code split into multiple files with comments (`Core`, `Capture`, `PageEvents`, `PageMobs`, `UI`)
- [x] Sort by Name, Kills, Zone; per-zone kill counts; Expanded view; saved settings
- [x] Hunting Log page v1: 3D models, grey overlay, stars at 10/50/100, paging
- [x] Interface number verified: 16001 matches the .toc
- [x] Tested in game: sorts, zone grouping, Expanded view, Hunting Log, and data + settings persist across full logout (SavedVariables works on the beta)

## Needs testing in game


---

## Mob Drops page - planned

Recommended order:

- [ ] Search box (filter by mob or item name) - `PageMobs.lua`
- [ ] Low-sample warning on drop rates (flag rates under ~20 kills; 1/1 = 100% is meaningless) - `PageMobs.lua`
- [ ] Click column headers to sort the drops table (Qty, ID, Drop rate) - `PageMobs.lua`
- [ ] Hide grey items toggle - `PageMobs.lua`
- [ ] Rarity coloring or filter (quality is already stored) - `PageMobs.lua`
- [ ] Summary line at top (total kills, unique mobs, total items) - `PageMobs.lua`
- [ ] First and last kill dates per mob - `Capture.lua` + `PageMobs.lua`
- [ ] Delete a mob entry (clean out test data) - `PageMobs.lua`
- [x] Coin row (gold coin picture, total, drop rate, hover details) at the top of each creature's loot list on the Mob Drops page and the Hunting Log detail page. Needs in-game test.

## Hunting Log - built (v1), planned improvements

Built: grid of creature cards (3D model, name, 3 stars at 10/50/100 kills), greyed until killed, paging. File: `PageHunt.lua`.
The creature list is built from creatures you have targeted or moused over, plus anything you have looted.

- [ ] Pre-loaded creature lists per zone (all creatures greyed from the start). Needs a data file built from outside the game, since addons can't list a zone's creatures.
- [ ] Zone filter and zone grouping
- [ ] Sort options (name, kills, killed first)
- [ ] Filter: killed only / not killed only
- [ ] Fix model framing if some creatures look too big or too small (camera settings)
- [ ] Better star art if the built-in star texture looks wrong
- [x] Kills with no loot window are counted when you were fighting the creature (`UNIT_DIED` + target watching, `Capture.lua`). Tested: unlooted kills count, no-loot kills count, looting does not double count, other players' kills are ignored. `/lootlog kills` shows what it decides. (The combat log is blocked on this client.)
- [ ] Untested edge case: a creature another player tagged while you have it targeted (should be ignored). Not counted by design: untargeted kills such as pets and area damage.
- [ ] Rename star tiers or add more tiers (`ns.HUNT_TIERS` in `Core.lua`)

---

## Hunting Log - zone lists (in progress)

Decisions so far: faction logs (A / H / AH), dungeons are their own zone, quest creatures get a note,
critters get their own tab per zone (Battle Pets count as critters), classes Elite / Rare / Boss are set in game.

- [x] Right-click a card to set Normal / Elite / Rare / Boss; stars at 1 / 5 / 10 for Elite, Rare, Boss (`PageHunt.lua`, `Core.lua`). Needs in-game test.
- [x] Zone selector, Creatures / Critters toggle, faction filter, per-creature zone/type recording (built, needs in-game test)
- [x] Plan: build zone lists by encountering creatures in game (target / mouse over). Upload SavedVariables `LootLog.lua` periodically so Claude can merge them into a data file.
- [x] Zone list loaded (`ZoneData.lua`, 1,594 zones with area IDs; 59 flagged UNUSED / test entries)
- [x] Starter data loaded: "neutral to Alliance" creatures (`Seed_A_Neutral.lua`, 255 creatures). Needs in-game test.
- [x] Seen / Unseen filter; all starter creatures and zones load from the start (switch `ns.ONLY_VISITED_ZONES` in `Core.lua` to load a zone only after you enter it). Needs in-game test.
- [x] Click a creature card to open its detail page: big model, stars, info, and its loot (`PageHunt.lua`). Needs in-game test.
- [x] Hunting Log is now the top menu item and opens first
- [ ] Creature description on the detail page (area reserved next to the model)
- [x] Type button cycles Creatures / Critters / All types; `/lootlog debug` prints what the Hunting Log loaded
- [x] `/lootlog faction A|H|all|mine` to view another faction's Hunting Log (testing option). Window title shows when it is not your own. Needs in-game test.
- [x] Faction badges on each card (yellow A / red A / yellow H / red H = neutral or hostile to that faction). Seeds carry a hostility field; in-game sightings record it when the creature is not in combat. Needs in-game test.
- [x] New classes on the right-click menu: Critter and Quest (with tags). Critter stars: 1 for seeing, 2 for a kill, 3 for 5 kills. Quest uses the normal 10 / 50 / 100 (change `quest` in `Core.lua` if you want different).
- [x] Zone menu has "Current zone" at the top (follows you); Type and Show are drop-downs
- [x] "Not in game version" option on the right-click menu: hides the creature but keeps it in saved data. Show > Not in version lists them; "Back in game version" restores. Needs in-game test.
- [ ] When you send your data: remove the flagged creatures from the starter lists and keep them in an archive file (so a mistake can be reversed)
- [x] Alliance-hostile list loaded (`Seed_A_Hostile.lua`, 1779 creatures, red A badge). Needs in-game test.
- [x] Horde lists loaded (`Seed_H_Neutral.lua` 187 creatures, `Seed_H_Hostile.lua` 1856 creatures). Creatures in both factions' lists show both badges. Needs in-game test. (send the CSVs; same columns, hostility like "H - Hostile")
- [ ] Check the zone name the game uses for the Barrens: the seed uses "The Barrens" (your list). If `/dump GetRealZoneText()` there says something else, the seed and your in-game data will split into two zones.
- [ ] Review the locations dropped from the seed (not in your zone list, mostly Northrend / Broken Isles / later zones) and 18 creatures with no location
- [ ] More seed files: Horde, hostile, and so on (copy `Seed_A_Neutral.lua`, change the faction, list it in the .toc)
- [ ] Zephras Isle: compile in game
- [ ] Decide what to do with the creature-type column (Beast, Humanoid...) beyond critter detection
- [ ] Quest creature marker and note
- [ ] Import your Elite / Rare / Boss choices (upload the SavedVariables `LootLog.lua`) into the data file later
- [ ] Option for creatures that drop no loot (needs a reliable kill event)

---

## Other logs - planned

- [x] **Gold capture** (`Capture.lua`) and the Gold page (`PageEvents.lua`): total, by source and zone, best creatures per kill. The coin amount is read from the coin slot's text (tested: type 2, quantity 0, text like "5 copper"). Needs in-game test.
- [ ] **Quest rewards**: capture (likely `QUEST_LOOT_RECEIVED`) feeds the Quest Rewards page. Page already exists but is empty.
- [ ] **Gathering**: proper detection. Right now the page reads the "Objects" category, which mixes ore/herb nodes with chests and other objects. Need to separate by profession.
- [ ] Items received outside the loot window (mail, vendor, crafting, trades) via `CHAT_MSG_LOOT`
- [ ] Possible extra event pages: Mail, Vendor, Crafting, Containers

## UI polish - planned

- [ ] Remember window and button positions across reloads
- [ ] Hover tooltips on the text pages (Fishing, Gathering, Quest) and the Expanded view
- [ ] Per-event tabs inside pages if the left menu gets crowded

## Export and database comparison (original goal)

- [ ] Export view: copyable text or CSV of the log
- [ ] Compare against item databases using item IDs. Likely an outside script run by you (the in-game addon can't call web APIs). Check whether Blizzard's web API covers the Forever client before relying on it.

---

## Known limits and issues

- Kills with no loot window (nothing dropped, not even coin) are never counted, so kill counts can run slightly low.
- Mobs you never targeted or moused over show as "ID 12345" instead of a name.
- The duplicate-loot guard resets on `/reload` or relog. Reopening a corpse after a reload can double count.
- If one corpse drops two separate stacks of the same item, the second stack is skipped.
- Old mob data has no per-zone counts, so zone totals can be lower than total kills until you kill more.
- Unverified on the Forever client: `GetLootSourceInfo` and GUID behavior under unit-info restrictions.
- Combat log events are not used on purpose (possibly restricted for addons). Revisit only if needed.
- VS Code shows strikethroughs on some old API functions (for example `GetItemIcon`, `tinsert`, loot slot functions). That's a deprecation warning, not an error. Ignore until something stops working.

## Ideas parking lot

(Add new ideas here, then move them into a section above when decided.)

-
# LootLog - Running List

Last updated: October 3, 2026

How to use: keep this file in your LootLog project folder (the .toc ignores it).
Tick boxes yourself in VS Code as things get done. I can't see your local copy,
so when you want it refreshed, tell me what changed and I'll regenerate it.

---

## Waiting on you

- [ ] Upload your SavedVariables file again whenever you have new data (`WTF\Account\<ACCOUNT>\SavedVariables\LootLog.lua`, after a `/reload`). First upload merged on 2026-10-03: your class choices went into `ClassData.lua` and the 14 Zephras Isle creatures into `Seed_Zephras_Isle.lua`. You had no "Not in game version" flags yet, so there was nothing to archive
- [ ] Zephras Isle: keep compiling in game (14 creatures so far, all met on a Horde character). Meeting them on an Alliance character adds the Alliance side
- [ ] Optional: fishing items per zone (add `zones = {["Durotar"] = true}` to rows in `FishData.lua`, or send a list) so each zone shows its full list greyed out with "caught / total"

## Needs testing in game

- [ ] **Rare drop messages**: a chat line for blue drops, a bigger one for epic and better (needs a blue or epic drop to see)
- [ ] **Zone complete messages**: when every creature on your list for a zone (your faction, no critters, no 'Not in game version') has been killed. Needs at least 5 creatures in the zone. Announced once per zone
- [ ] The **version number** line on the Help page (the `## Version:` line of `LootLog.toc`; it should read 1.0.0, not "unknown")

---

## Next up

Nothing queued. Pick from the ideas below, or add something to the parking lot.

### Someday, for fun
Not needed for the addon. Written a few at a time, whenever you feel like it.

- [ ] **Creature lore on the Hunting Log detail page** (the area next to the model is reserved). Revealed in stages as you earn stars, 4 short texts per creature:
  1. on meeting it
  2. on the 1st star
  3. on the 2nd star
  4. on the 3rd star
  Plan: a data file (for example `CreatureLore.lua`) with `[npcID] = { "met text", "star 1 text", "star 2 text", "star 3 text" }`. A creature with no entry shows nothing. Locked stages show as hidden ("???") so you can see there is more to find. Texts can be added over time, a few creatures per session
  Open points for when we build it: creatures with fewer than 3 stars (quest creatures have 1; critters earn their first star for seeing them) need a rule for how the 4 stages map onto their stars; and whether the stages should unlock per character or for the whole account
- [ ] **Notes box on each creature's detail page**: a place to write your own notes about a creature, saved with your data. Plan: a multi-line text box on the detail page, saved when you click away. Proposed: notes are shared by all characters (like class choices), because they are about the creature, not the character. Notes stay in your saved file, so they are covered by your SavedVariables backups

### Fishing Log - remaining ideas
- [ ] Review the section grouping at the bottom of `FishData.lua` (Gear is 441 items)

### UI polish
- [ ] Hover tooltips on the text pages (Gathering, Quest, Gold) and the Expanded view
- [ ] Per-event tabs inside pages if the left menu gets crowded

---

## Done

**Capture**
- [x] Loot from the loot window, works with auto loot; item IDs, links, icons, quantities
- [x] Duplicate guards (reopening a corpse, LOOT_OPENED + LOOT_READY both firing)
- [x] Kills counted for coin-only corpses, and for kills with no loot window (`UNIT_DIED` + target watching). The combat log is blocked on this client. `/lootlog kills` shows what it decides
- [x] Coin: read from the coin slot text; Gold page with totals, by source and zone, best creatures per kill; coin row (gold coin picture) on Mob Drops and the Hunting Log detail page
- [x] Quest rewards, quest coin, and every turned-in quest (Completed Quests tab)
- [x] Gathering told apart by the spell you cast (Mining, Herb gathering, Skinning); per node with the node's name; skinning kept out of creature drops
- [x] Elite / Rare / Boss set automatically from the game's classification when you target or mouse over a creature (your right-click choice wins)

**Pages**
- [x] Main window, left menu, open button, `/lootlog` commands (`reset`, `debug`, `kills`, `faction`)
- [x] Hunting Log: 3D model cards, stars, zone / type / show drop-downs, "Current zone", faction badges (yellow = neutral, red = hostile), detail page with loot, right-click classes (Normal, Elite, Rare, Boss, Critter, Quest), "Not in game version" flag, Seen / Unseen
- [x] Starter data: zone list (1,594 zones), creature lists (Alliance neutral and hostile, Horde neutral and hostile: 2,478 unique creatures), fishing list (681 items)
- [x] Mob Drops: sort by name / kills / zone, Expanded view, drop rates, summary line, search box, first / last kill dates, rarity filter, clickable column headings, right-click delete a creature
- [x] Gathering page by zone > kind > node, with icons
- [x] Fishing Log journal with stars
- [x] Received Items page: Vendor, Mail, Crafting, Trades, Other tabs, with item pictures
- [x] Recent sort (Mob Drops and Hunting Log), creature type in the Hunting Log tooltip and detail page, star messages in chat (`Messages.lua`, `/lootlog messages`). All confirmed in game
- [x] Hunting Log: Sort drop-down (name, kills, killed first, not killed first), Killed / Not killed filters, count on the zone button
- [x] Remembered window and button positions
- [x] Confirmed in game (2026-10-03): quest rewards, gathering node icons, fishing stars, right-click menu, rarity filter and the newest features, and that a creature another player tagged is ignored. The Barrens is a single zone in this version, so the starter data's "The Barrens" matches
- [x] Confirmed in game (2026-10-03): Mob Drops (including first / last kill with date and time), quest creatures with one star, Help tab, `/lootlog reset` confirmation window, `/lootlog button`, creature tooltip line, Session page, per-character data with the All characters check box, previous session, and message levels (Reduce / Stop messages)
- [x] Code split into files with comments; saved data and settings survive logout; Interface number verified (16001)

---

## Known limits and issues

- The starter lists come from CSV files and do not cover new Forever beta zones such as Zephras Isle. Those fill in from your own play
- Kills of creatures you never targeted (pets, area damage) and creatures other players tagged are not counted
- Mobs you never targeted or moused over show as "ID 12345" instead of a name
- The duplicate-loot guard resets on `/reload` or relog, so reopening a corpse after a reload can double count
- If one corpse drops two separate stacks of the same item, the second stack is skipped
- Old mob data has no per-zone counts, so zone totals can be lower than total kills for those creatures
- Gathering you did before node tracking is listed as "Earlier gathers (node not recorded)"
- If you start a gather, cancel it, and loot an ordinary object within 10 seconds, it can be miscategorized
- Stars on fish count catches in all zones added together
- VS Code shows strikethroughs on some old API functions (for example `GetItemIcon`, `tinsert`). That is a deprecation warning, not an error. Ignore until something stops working

## Held for later (not needed yet)

- [ ] **Cache the Hunting Log list.** The page rebuilds its whole creature list (about 4,000 starter rows plus what you have met) on every redraw. I expect that to take only a few milliseconds, so it is on hold. If the Hunting Log ever feels slow: first add a `/lootlog timing` command to measure a rebuild; if it takes more than about 20 ms, do the cheap version (pre-index the starter lists once, since they never change during a session, and rebuild only your own data each time). A full cache is riskier because it can go stale: the list depends on kills, sightings, class choices, flags, the faction being viewed, and the filters

## Decided not to do

- Model framing and star art changes (both look fine as they are; can be revisited)
- CSV / text export of the log (can be added later if wanted)
- Comparing against item databases (it needed the export; the saved file can also be used directly if ever wanted)
- Low drop-rate warning (greyed rates with a star): removed
- Hide grey items toggle (the rarity filter covers it if ever wanted)

## Ideas parking lot

(Add new ideas here, then move them into a section above when decided.)

-
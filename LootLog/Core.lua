--[[
=====================================================================
 Core.lua - shared foundation for every other file
=====================================================================

 HOW FILES SHARE DATA:
   The first line of every file, "local ADDON, ns = ...", gives that
   file two values from the game: the addon name and a table (ns)
   that is THE SAME TABLE in every file of this addon. Anything put on
   ns here is visible to all other files. That is how the files talk
   to each other without using globals.

 FILE MAP:
   Core.lua        this file: shared variables, database, helpers
   Capture.lua     reads the loot window, writes to the database
   PageEvents.lua  text pages: Fishing, Gathering, Quest, Gold
   PageMobs.lua    the two-pane Mob Drops page
   UI.lua          window, left menu, open button, slash command

 SAVED DATA (LootLogDB, written to disk on /reload or logout):
   LootLogDB = {
     mobs = {
       [npcID] = {
         name  = "Mob name",
         zone  = "Last zone looted in",
         kills = number of looted corpses,
         items = { [itemID] = { drops = times it dropped, qty = total quantity } },
       },
     },
     events = {                     -- non-mob log, one table per category
       ["Fishing"] = { ["Zone name"] = { [itemID] = { name, quality, count } } },
       ["Objects"] = { ... },       -- ore/herb nodes, chests, etc.
     },
     items = { [itemID] = itemLink },   -- link per item (name + color + tooltip)
     icons = { [itemID] = iconTexture },
   }

 DROP RATE = it.drops / m.kills
   "drops" counts corpses that dropped the item, not how many items.
   "qty" is the total item count. The two differ for stackable loot.

 DEBUGGING:
   /console scriptErrors 1   shows Lua errors in a popup
   /dump LootLogDB           prints the live data table in chat
   /lootlog reset            wipes all saved data
=====================================================================
]]

local ADDON, ns = ...

-- ===== SESSION VARIABLES (reset on every /reload or login) =====
-- These are NOT saved to disk. They only prevent double counting
-- while the game is running.
--
-- IMPORTANT: never reassign these (ns.seen = {}). Other files keep their
-- own local pointer to the same table, and reassigning would leave them
-- pointing at the old one. To empty them, use wipe(ns.seen).
ns.seen = {}     -- corpse GUIDs already counted as a kill this session
ns.counted = {}  -- "corpseGUID:itemID" pairs already logged this session
                 -- (stops reopening the same corpse from double counting)
ns.names = {}    -- npcID -> mob name cache, filled by targeting/mouseover

-- ===== UI STATE shared between files =====
ns.currentPage = "hunt"   -- which left-menu page is showing (opens on the Hunting Log)
ns.selectedMob = nil      -- npcID selected in the Mob Drops list

-- The loot slot type value for "item". Newer clients provide it as
-- Enum.LootSlotType.Item. The global LOOT_SLOT_ITEM was nil on this client,
-- which is why the fallback of 1 exists.
ns.ITEM_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
-- Same for coin: a loot slot of this type holds money. (Tested: type 2.)
ns.MONEY_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2


-- ===== DATABASE ACCESS =====
-- Always get the database through ns.DB() so it exists even on a brand
-- new install. LootLogDB is the global declared in the .toc file's
-- "## SavedVariables:" line, which is what the game saves to disk.
function ns.DB()
  LootLogDB = LootLogDB or { events = {}, mobs = {} }
  return LootLogDB
end


-- ===== DISPLAY HELPERS =====

-- Item display text: the colored item link if we have it, else a fallback.
function ns.ItemText(db, itemID, fallback)
  return (db.items and db.items[itemID]) or fallback or "item"
end

-- Item icon: stored icon first, then ask the game client if missing.
function ns.GetIcon(db, itemID)
  if db.icons and db.icons[itemID] then return db.icons[itemID] end
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
  if GetItemIcon then return GetItemIcon(itemID) end
end


-- ===== SETTINGS (saved inside LootLogDB, so they survive /reload) =====
-- Returns the settings table, filling in defaults for anything missing.
--   sort     = "name", "kills", or "zone"  (Mob Drops list order)
--   expanded = true shows the one-big-list view on the Mob Drops page
-- Add a new setting by giving it a default here.
function ns.Settings()
  local db = ns.DB()
  db.settings = db.settings or {}
  if db.settings.sort == nil then db.settings.sort = "name" end
  if db.settings.expanded == nil then db.settings.expanded = false end
  -- Hunting Log: which zone is selected ("All" = every zone) and which list
  -- is showing ("creatures" or "critters")
  if db.settings.huntZone == nil then db.settings.huntZone = "All" end
  if db.settings.huntView == nil then db.settings.huntView = "creatures" end
  -- Hunting Log seen filter: "all", "seen" (met in game) or "unseen" (starter list only)
  if db.settings.huntSeen == nil then db.settings.huntSeen = "all" end
  -- Hunting Log faction being viewed (a testing option, set with /lootlog faction):
  -- "mine" = your character's faction, "A" = Alliance log, "H" = Horde log, "all" = everything
  if db.settings.huntFaction == nil then db.settings.huntFaction = "mine" end
  return db.settings
end


-- ===== PER-ZONE KILL TRACKING =====
-- Mob data now has an optional m.zones = { ["Zone name"] = kills }.
-- Mobs recorded before this existed only have m.zone (the last zone seen).

-- Counts one kill for mob table m in the given zone. Use this instead of
-- "m.kills = m.kills + 1" so kills and the per-zone counts stay in step.
function ns.CountKill(m, zone)
  m.kills = m.kills + 1
  m.zones = m.zones or {}
  m.zones[zone] = (m.zones[zone] or 0) + 1
end

-- Returns the zone a mob is mostly killed in (most kills). Ties go to the
-- alphabetically first zone so the result never flips between redraws.
-- Falls back to the old single m.zone for mobs without per-zone data.
function ns.PrimaryZone(m)
  local best, bestKills
  if m.zones then
    for zone, kills in pairs(m.zones) do
      if not bestKills or kills > bestKills or (kills == bestKills and zone < best) then
        best, bestKills = zone, kills
      end
    end
  end
  return best or m.zone or "Unknown"
end


-- ===== HUNTING LOG SETTINGS =====
-- Kill counts at which a creature earns its 1st, 2nd and 3rd star.
-- Change these numbers to retune the stars; PageHunt.lua reads them.
ns.HUNT_TIERS = { 10, 50, 100 }

-- Current page of the Hunting Log grid (1 = first page). Session only.
ns.huntPage = 1


-- ===== CREATURE CLASSES (Normal / Elite / Rare / Boss) =====
-- You mark a creature's class in game (right-click its card in the Hunting
-- Log). Choices are saved in LootLogDB.classes[npcID]; a creature with no
-- entry is "normal". The class decides how many kills earn each star.
-- Edit the numbers here to retune; PageHunt.lua reads them.
ns.HUNT_TIERS_BY_CLASS = {
  normal = ns.HUNT_TIERS,   -- 10 / 50 / 100 (defined above)
  elite  = { 1, 5, 10 },
  rare   = { 1, 5, 10 },    -- assumed same as elite; change if you want different
  boss   = { 1, 5, 10 },
  -- Critters: the FIRST star is for seeing the critter (handled in PageHunt.lua).
  -- These two numbers are the kills for the 2nd and 3rd star.
  critter = { 1, 5 },
  quest  = ns.HUNT_TIERS,   -- quest mobs use the normal numbers; change if you want
}

-- Display names for each class (used on the menu and the card tag)
ns.CLASS_LABELS = {
  normal = "Normal", elite = "Elite", rare = "Rare", boss = "Boss",
  critter = "Critter", quest = "Quest",
}

-- When true, a creature you never classified by hand gets a default class
-- from what the game reports when you target it (elite, rare, or world
-- boss). Your own right-click choice always wins over this default.
-- Set to false to make everything "normal" until you classify it yourself.
ns.USE_GAME_CLASSIFICATION = true

-- Maps the game's UnitClassification() text to our classes
local AUTO_CLASS = { elite = "elite", rare = "rare", rareelite = "rare", worldboss = "boss" }

-- Returns the creature's class: "normal", "elite", "rare", "boss",
-- "critter", or "quest":
--   1. your saved choice (including an explicit "normal"), else
--   2. "critter" if the creature is a critter type (isCritter = true), else
--   3. the game's classification recorded when you saw it, else
--   4. "normal"
function ns.GetClass(db, npcID, isCritter)
  local chosen = db.classes and db.classes[npcID]
  if chosen then return chosen end
  if isCritter then return "critter" end
  if ns.USE_GAME_CLASSIFICATION then
    local k = db.known and db.known[npcID]
    if type(k) == "table" and k.uclass then return AUTO_CLASS[k.uclass] or "normal" end
  end
  return "normal"
end

-- Saves a creature's class. "normal" is saved too (not removed), so a
-- creature the game calls elite stays normal if you say so.
function ns.SetClass(npcID, class)
  local db = ns.DB()
  db.classes = db.classes or {}
  db.classes[npcID] = class
end

-- Returns the star thresholds for a class (falls back to the normal ones)
function ns.TiersFor(class)
  return ns.HUNT_TIERS_BY_CLASS[class] or ns.HUNT_TIERS
end


-- ===== SEEN-CREATURE RECORDS (db.known) =====
-- db.known[npcID] = {
--   name   = "Creature name",
--   zones  = { ["Zone name"] = true },      -- zones you saw it in
--   fac    = { A = true, H = true },        -- which faction's characters saw it
--   ctype  = "Beast",                       -- creature type from the game
--   uclass = "elite",                       -- classification from the game
-- }
-- Older saves stored just the name as text; GetKnown upgrades those.

-- Returns the record for a creature (upgrading an old name-only entry),
-- or nil if the creature was never seen.
function ns.GetKnown(db, npcID)
  local k = db.known and db.known[npcID]
  if type(k) == "string" then
    k = { name = k }
    db.known[npcID] = k
  end
  return k
end

-- Returns the record for a creature, creating it if needed.
function ns.TouchKnown(npcID, name)
  local db = ns.DB()
  db.known = db.known or {}
  local k = ns.GetKnown(db, npcID)
  if not k then
    k = { name = name }
    db.known[npcID] = k
  end
  k.name = name or k.name
  return k
end

-- "A" for Alliance, "H" for Horde, nil if the game doesn't say.
function ns.PlayerFaction()
  local f = UnitFactionGroup("player")
  if f == "Alliance" then return "A" end
  if f == "Horde" then return "H" end
  return nil
end

-- True for creature types that belong on the Critters tab. Battle Pets
-- do not exist in this game version, so they count as critters, as do
-- the game's "Non-combat Pet" creatures.
function ns.IsCritterType(ctype)
  return ctype == "Critter" or ctype == "Non-combat Pet" or ctype == "Battle Pet"
end


-- ===== VISITED PLACES (decides which starter creatures load) =====
-- db.visited = { ["Durotar"] = true, ["Deathknell"] = true, ... }
-- Recorded as you play. Used only when ns.ONLY_VISITED_ZONES (below) is true,
-- to hold back a zone's starter creatures (Seed_*.lua files) until you enter it.

-- Returns the names of where you are standing: the zone, plus the sub-zone
-- when that sub-zone is also in the zone list (ZoneData.lua). Sub-zones
-- matter for starting areas such as Deathknell, which the game reports as
-- a sub-zone of Tirisfal Glades.
function ns.CurrentPlaces()
  local places = {}
  local zone = GetRealZoneText()
  if zone and zone ~= "" then places[#places + 1] = zone end
  local sub = GetSubZoneText()
  if sub and sub ~= "" and sub ~= zone and ns.ZONE_IDS and ns.ZONE_IDS[sub] then
    places[#places + 1] = sub
  end
  return places
end

-- Records where you are standing as visited.
function ns.NoteVisited()
  local db = ns.DB()
  db.visited = db.visited or {}
  for _, place in ipairs(ns.CurrentPlaces()) do db.visited[place] = true end
end

-- Hunting Log: when true, a zone's starter creatures (Seed_*.lua) only appear
-- after you have entered that zone. When false (default), every starter
-- creature and every zone is available from the start.
ns.ONLY_VISITED_ZONES = false


-- ===== WHICH FACTION'S HUNTING LOG IS SHOWING =====
-- Normally your character's own faction. /lootlog faction A|H|all|mine can
-- override it, which is useful for testing (for example previewing the
-- Alliance starter list on a Horde character). Returns "A", "H", or nil;
-- nil means "show every creature whatever its faction".
function ns.ViewFaction()
  local choice = ns.Settings().huntFaction
  if choice == "A" or choice == "H" then return choice end
  if choice == "all" then return nil end
  return ns.PlayerFaction()   -- "mine"
end


-- ===== "NOT IN GAME VERSION" FLAG =====
-- db.notInGame = { [npcID] = true }
-- A creature you mark "Not in game version" is hidden from the Hunting Log
-- (it stays in your saved data, so a mistake can be undone). View the
-- flagged creatures with Show > Not in version, then right-click one and
-- choose "Back in game version" to restore it.
-- When you send your data later, Claude can remove these creatures from the
-- starter lists and keep them in an archive file in case of a mistake.

-- True if the creature is marked "not in game version".
function ns.IsNotInGame(db, npcID)
  return db.notInGame ~= nil and db.notInGame[npcID] == true
end

-- Marks (flag = true) or restores (flag = false) a creature.
function ns.SetNotInGame(npcID, flag)
  local db = ns.DB()
  db.notInGame = db.notInGame or {}
  db.notInGame[npcID] = flag and true or nil
end


-- ===== MONEY TEXT =====
-- Turns an amount in copper into text with coin icons (for example
-- 12 gold 34 silver 56 copper). Falls back to plain text if the game's
-- coin formatter is missing.
function ns.FormatMoney(copper)
  copper = math.floor(copper or 0)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  return string.format("%dg %ds %dc", g, s, c)
end


-- ===== COIN ROW (shown at the top of a creature's loot list) =====
-- The gold coin picture used for the coin row.
ns.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Tooltip lines for a creature's coin row. m is its record in db.mobs
-- (m.gold = total copper, m.goldDrops = corpses that dropped coin);
-- kills is its kill count. The first line is the title.
function ns.CoinTipLines(m, kills)
  local drops = m.goldDrops or 0
  local lines = { "Coin", "Total: " .. ns.FormatMoney(m.gold) }
  if drops > 0 then
    lines[#lines + 1] = "Average per drop: " .. ns.FormatMoney(math.floor(m.gold / drops))
  end
  if kills > 0 then
    lines[#lines + 1] = "Average per kill: " .. ns.FormatMoney(math.floor(m.gold / kills))
  end
  lines[#lines + 1] = string.format("Dropped on %d of %d kills", drops, kills)
  return lines
end
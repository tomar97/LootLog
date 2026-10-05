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
   Each CHARACTER has its own record, so what you see is the character you
   are playing (or everyone combined, with the "All characters" check box).
   LootLogDB = {
     chars = {                          -- one record per character, "Name-Realm"
       ["Tyler-Realm"] = {
         mobs = {                       -- creatures killed
           [npcID] = { name, zone, kills, items = { [itemID] = { drops, qty } }, ... },
         },
         known = { ... },               -- creatures this character has met
         events = { ["Fishing"] = { ["Zone"] = { [itemID] = { name, quality, count } } }, ... },
         gold, quests, gather, visited, zonesDone,
         faction, lastSeen, ...
       },
     },
     -- Shared by every character:
     settings = { ... },                -- window, filters, sorts, switches
     classes = { [npcID] = "elite" },   -- your class choices (a creature is the same for everyone)
     notInGame = { [npcID] = true },    -- your "Not in game version" flags
     items = { [itemID] = itemLink },   -- item links (name + colour + tooltip)
     icons = { [itemID] = iconTexture },
     nodeNames = { ... },               -- names of gathering nodes
   }
 Code reads and writes THIS character through ns.DB(). Pages read through
 ns.ViewDB(), which is this character, or everyone combined (read-only).

 DROP RATE = it.drops / m.kills
   "drops" counts corpses that dropped the item, not how many items.
   "qty" is the total item count. The two differ for stackable loot.

 DEBUGGING:
   /console scriptErrors 1   shows Lua errors in a popup
   /dump LootLogDB           prints the live data table in chat
   /lootlog reset            wipes this character's saved data (it asks first)
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


-- ===== DATABASE ACCESS: ONE RECORD PER CHARACTER =====
-- LootLogDB is the global declared in the .toc file's "## SavedVariables:"
-- line, which is what the game saves to disk (one file for the whole account).
-- Inside it, each character has its own record in LootLogDB.chars. Some things
-- are the same for every character and are kept at the top level instead.

-- Parts of the data that belong to one character
local PER_CHARACTER = { "mobs", "known", "events", "gold", "moneyIn", "vendors", "sales", "crafting", "trades",
                        "quests", "gather", "visited", "zonesDone" }

-- Parts shared by every character
local SHARED = { settings = true, classes = true, notInGame = true,
                 items = true, icons = true, nodeNames = true, questItems = true }

local root, cur, curKey   -- remembered between calls so lookups stay cheap

-- "Name-Realm" for the character you are playing.
function ns.CharKey()
  if not curKey then
    local name = UnitName("player")
    if not name or name == "Unknown" then return "Unknown-" .. (GetRealmName and GetRealmName() or "") end
    curKey = name .. "-" .. (GetRealmName and GetRealmName() or "")
  end
  return curKey
end

-- Data from before characters were kept apart is one flat table. Move the
-- per-character parts into the record of the character playing now (it cannot
-- be split between characters afterwards).
local function Migrate(r)
  r.chars = {}
  r.dataVersion = 2
  local old = {}
  for _, k in ipairs(PER_CHARACTER) do
    if r[k] ~= nil then old[k] = r[k]; r[k] = nil end
  end
  if next(old) ~= nil then
    old.mobs = old.mobs or {}
    old.events = old.events or {}
    old.known = old.known or {}
    old.visited = old.visited or {}
    old.firstSeen = time()
    local key = ns.CharKey()
    r.chars[key] = old
    ns.migratedTo = key   -- the login code tells you
  end
end

-- The top-level table, created on a brand new install, migrated if old.
local function Root()
  local r = LootLogDB
  if not r then r = {}; LootLogDB = r end
  if r ~= root then root = r; cur = nil end   -- (the game replaces the table when it loads saved data)
  if not r.chars then Migrate(r) end
  return r
end

-- The record of the character playing now, created the first time.
local function CharData()
  local r = Root()
  if not cur then
    local key = ns.CharKey()
    cur = r.chars[key]
    if not cur then
      cur = { firstSeen = time() }
      r.chars[key] = cur
      ns.newCharacter = key   -- the login code welcomes it
    end
    -- parts the rest of the code expects to exist
    cur.mobs = cur.mobs or {}
    cur.known = cur.known or {}
    cur.events = cur.events or {}
    cur.visited = cur.visited or {}
  end
  return cur
end

-- ns.DB() is what the capture code uses. It looks like one flat table: a
-- shared part (settings, classes...) is read and written at the top level, and
-- everything else goes to the character playing now.
local proxy = setmetatable({}, {
  __index = function(_, k)
    if SHARED[k] then return Root()[k] end
    return CharData()[k]
  end,
  __newindex = function(_, k, v)
    if SHARED[k] then Root()[k] = v else CharData()[k] = v end
  end,
})

function ns.DB()
  return proxy
end

-- Everyone's data added together, as one flat table shaped like a character's
-- data (read-only: changing it changes nothing that is saved).
local function MergeAll(r)
  local out = {
    mobs = {}, known = {}, events = {}, quests = {}, gather = {}, visited = {}, zonesDone = {},
    moneyIn = {}, vendors = {}, sales = {}, crafting = {}, trades = {}, questItems = r.questItems or {},
    gold = { total = 0, drops = 0, events = {} },
    settings = r.settings, classes = r.classes, notInGame = r.notInGame,
    items = r.items, icons = r.icons, nodeNames = r.nodeNames,
  }
  for _, c in pairs(r.chars) do
    -- Creatures killed: add kills, drops, quantities, coin; keep the earliest first kill and latest last kill
    for npcID, m in pairs(c.mobs or {}) do
      local o = out.mobs[npcID]
      if not o then o = { name = m.name, kills = 0, items = {}, zones = {} }; out.mobs[npcID] = o end
      o.name = o.name or m.name
      o.zone = m.zone or o.zone
      o.kills = o.kills + (m.kills or 0)
      for z, n in pairs(m.zones or {}) do o.zones[z] = (o.zones[z] or 0) + n end
      for itemID, it in pairs(m.items or {}) do
        local oi = o.items[itemID]
        if not oi then oi = { drops = 0, qty = 0 }; o.items[itemID] = oi end
        oi.drops = oi.drops + (it.drops or 0)
        oi.qty = oi.qty + (it.qty or 0)
      end
      if m.gold then
        o.gold = (o.gold or 0) + m.gold
        o.goldDrops = (o.goldDrops or 0) + (m.goldDrops or 0)
      end
      if m.firstKill and (not o.firstKill or m.firstKill < o.firstKill) then o.firstKill = m.firstKill end
      if m.lastKill and (not o.lastKill or m.lastKill > o.lastKill) then o.lastKill = m.lastKill end
    end

    -- Creatures met: join zones and factions; keep the first answer for the rest
    for npcID, k in pairs(c.known or {}) do
      if type(k) == "string" then k = { name = k } end   -- very old name-only entries
      local o = out.known[npcID]
      if not o then o = { name = k.name, zones = {}, host = {} }; out.known[npcID] = o end
      o.name = o.name or k.name
      o.ctype = o.ctype or k.ctype
      o.uclass = o.uclass or k.uclass
      if k.lastSeen and (not o.lastSeen or k.lastSeen > o.lastSeen) then o.lastSeen = k.lastSeen end
      for z in pairs(k.zones or {}) do o.zones[z] = true end
      if k.fac then
        o.fac = o.fac or {}
        for f in pairs(k.fac) do o.fac[f] = true end
      end
      for f, state in pairs(k.host or {}) do o.host[f] = o.host[f] or state end
    end

    -- Items by category, zone, and item
    for cat, zones in pairs(c.events or {}) do
      local oc = out.events[cat]
      if not oc then oc = {}; out.events[cat] = oc end
      for zone, items in pairs(zones) do
        local oz = oc[zone]
        if not oz then oz = {}; oc[zone] = oz end
        for itemID, e in pairs(items) do
          local oe = oz[itemID]
          if not oe then oe = { name = e.name, quality = e.quality, count = 0 }; oz[itemID] = oe end
          oe.count = oe.count + (e.count or 0)
          oe.quality = oe.quality or e.quality
        end
      end
    end

    -- Gold received from vendors, mail, and trades
    for cat, mi in pairs(c.moneyIn or {}) do
      local o = out.moneyIn[cat]
      if not o then o = { total = 0, times = 0, zones = {} }; out.moneyIn[cat] = o end
      o.total = o.total + (mi.total or 0)
      o.times = o.times + (mi.times or 0)
      for zone, n in pairs(mi.zones or {}) do o.zones[zone] = (o.zones[zone] or 0) + n end
    end

    -- Vendors: what you sold to and bought from each one, by zone
    for zone, names in pairs(c.vendors or {}) do
      local oz = out.vendors[zone]
      if not oz then oz = {}; out.vendors[zone] = oz end
      for vname, v in pairs(names) do
        local ov = oz[vname]
        if not ov then ov = { sold = 0, soldTimes = 0, bought = {} }; oz[vname] = ov end
        ov.sold = ov.sold + (v.sold or 0)
        ov.soldTimes = ov.soldTimes + (v.soldTimes or 0)
        for itemID, qty in pairs(v.bought or {}) do ov.bought[itemID] = (ov.bought[itemID] or 0) + qty end
      end
    end

    -- What you sold of each item (to vendors and at the auction house)
    for itemID, s in pairs(c.sales or {}) do
      local o = out.sales[itemID]
      if not o then o = { vendorCount = 0, vendorGold = 0, aucCount = 0, aucGold = 0 }; out.sales[itemID] = o end
      o.vendorCount = o.vendorCount + (s.vendorCount or 0)
      o.vendorGold = o.vendorGold + (s.vendorGold or 0)
      o.aucCount = o.aucCount + (s.aucCount or 0)
      o.aucGold = o.aucGold + (s.aucGold or 0)
    end

    -- Things you crafted, by kind of crafting
    for craftType, items in pairs(c.crafting or {}) do
      local o = out.crafting[craftType]
      if not o then o = {}; out.crafting[craftType] = o end
      for itemID, n in pairs(items) do o[itemID] = (o[itemID] or 0) + n end
    end

    -- Trades: all characters' trades in one list, newest first
    for _, t in ipairs(c.trades or {}) do out.trades[#out.trades + 1] = t end

    -- Coin
    local g = c.gold
    if g then
      out.gold.total = out.gold.total + (g.total or 0)
      out.gold.drops = out.gold.drops + (g.drops or 0)
      for cat, zones in pairs(g.events or {}) do
        local oc = out.gold.events[cat]
        if not oc then oc = {}; out.gold.events[cat] = oc end
        for zone, n in pairs(zones) do oc[zone] = (oc[zone] or 0) + n end
      end
    end

    -- Quests: keep the most recent turn-in of each, and add up how often
    for qid, q in pairs(c.quests or {}) do
      local o = out.quests[qid]
      if not o or (q.t or 0) > (o.t or 0) then
        local before = o and (o.count or 1) or 0
        o = {}
        for key, value in pairs(q) do o[key] = value end
        o.count = (q.count or 1) + before
        out.quests[qid] = o
      else
        o.count = (o.count or 1) + (q.count or 1)
      end
    end

    -- Gathering nodes
    for cat, zones in pairs(c.gather or {}) do
      local oc = out.gather[cat]
      if not oc then oc = {}; out.gather[cat] = oc end
      for zone, nodes in pairs(zones) do
        local oz = oc[zone]
        if not oz then oz = {}; oc[zone] = oz end
        for key, n in pairs(nodes) do
          local on = oz[key]
          if not on then on = { id = n.id, kind = n.kind, gathers = 0, items = {} }; oz[key] = on end
          on.gathers = on.gathers + (n.gathers or 0)
          for itemID, qty in pairs(n.items or {}) do on.items[itemID] = (on.items[itemID] or 0) + qty end
        end
      end
    end

    for place in pairs(c.visited or {}) do out.visited[place] = true end
    for zone, t in pairs(c.zonesDone or {}) do
      if not out.zonesDone[zone] or t < out.zonesDone[zone] then out.zonesDone[zone] = t end
    end
  end
  return out
end

-- What the pages show: this character's data, or everyone's added together
-- when "All characters" is ticked (ns.Settings().allChars). A plain table,
-- fast to read.
function ns.ViewDB()
  local r = Root()
  if ns.Settings().allChars then return MergeAll(r) end
  local c = CharData()
  return {
    mobs = c.mobs, known = c.known, events = c.events, gold = c.gold, quests = c.quests,
    gather = c.gather, visited = c.visited, zonesDone = c.zonesDone, moneyIn = c.moneyIn, vendors = c.vendors,
    sales = c.sales, crafting = c.crafting, trades = c.trades,
    settings = r.settings, classes = r.classes, notInGame = r.notInGame,
    items = r.items, icons = r.icons, nodeNames = r.nodeNames, questItems = r.questItems,
  }
end

-- Notes who is playing: faction, class, level, and when. Called at login.
function ns.TouchCharacter()
  local c = CharData()
  c.faction = ns.PlayerFaction() or c.faction
  local _, class = UnitClass("player")
  c.class = class or c.class
  c.level = UnitLevel("player") or c.level
  c.lastSeen = time()
end

-- Removes this character's data (the others, the settings, class choices,
-- and flags are kept). A fresh record is made the next time it is needed.
function ns.ResetCharacter()
  local r = Root()
  r.chars[ns.CharKey()] = nil
  cur = nil
end

-- Every character with data: { key, faction, kills, lastSeen, current }.
function ns.CharList()
  local r = Root()
  local list = {}
  for key, c in pairs(r.chars) do
    local kills = 0
    for _, m in pairs(c.mobs or {}) do kills = kills + (m.kills or 0) end
    list[#list + 1] = { key = key, faction = c.faction, kills = kills,
                        lastSeen = c.lastSeen, current = (key == ns.CharKey()) }
  end
  table.sort(list, function(a, b) return a.key < b.key end)
  return list
end

-- The window title: "LootLog", or with a note when you are looking at everyone.
function ns.TitleBase()
  if ns.Settings().allChars then return "LootLog - all characters" end
  return "LootLog"
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
  -- Which tab is selected on pages that have tabs, for example
  -- subtabs.quest = "completed" (see ns.SUBTABS in PageEvents.lua)
  db.settings.subtabs = db.settings.subtabs or {}
  -- Where you left the window and the open button: positions.window / .button
  db.settings.positions = db.settings.positions or {}
  -- Mob Drops: the drops table sort (heading clicked: "name", "id", "qty" or
  -- "rate") and its direction, and the rarity filter ("all", "poor", "common",
  -- "uncommon", "rare", "epic")
  if db.settings.dropSort == nil then db.settings.dropSort = "rate" end
  if db.settings.dropDesc == nil then db.settings.dropDesc = true end
  if db.settings.rarity == nil then db.settings.rarity = "all" end
  -- Hunting Log sort: "name", "kills", "killed" (killed first) or "unkilled"
  if db.settings.huntSort == nil then db.settings.huntSort = "name" end
  -- Chat messages when you earn a star (/lootlog messages turns them off)
  if db.settings.starMessages == nil then db.settings.starMessages = true end
  -- How chatty LootLog is: "all", "reduced" (only stars, rare drops, zone clears) or "off".
  -- Replaces the old on/off switch: anyone who had messages off keeps them off.
  if db.settings.messageLevel == nil then
    db.settings.messageLevel = (db.settings.starMessages == false) and "off" or "all"
  end
  -- The on-screen LootLog button (/lootlog button) and the creature tooltip line (/lootlog tooltip)
  if db.settings.hideButton == nil then db.settings.hideButton = false end
  -- Show every character's data combined instead of just this character's (the "All characters" check box)
  if db.settings.allChars == nil then db.settings.allChars = false end
  if db.settings.tooltipLine == nil then db.settings.tooltipLine = true end
  -- Fishing Log: which zone is selected ("@current", "All", or a zone name)
  -- and the Show filter ("all", "caught", "notcaught")
  if db.settings.fishZone == nil then db.settings.fishZone = "All" end
  if db.settings.fishShow == nil then db.settings.fishShow = "all" end
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
  -- When the first and the latest kill happened (kills from before this
  -- was added have no first date)
  local now = time()
  m.firstKill = m.firstKill or now
  m.lastKill = now
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
  quest  = { 1 },           -- quest mobs: ONE star in total, earned on the first kill (quest bosses can be killed once)
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

-- ===== A CREATURE'S CLASS (designation) =====
-- Classes: "normal", "elite", "rare", "boss", "critter", "quest".
-- The designation (elite / rare / boss) comes from the creature list in
-- Seed_Creatures.lua. You normally only mark quest creatures, since the list
-- cannot know which creatures are quest creatures, or change a designation
-- you think is wrong. Both are saved in db.classes (shared by all characters).

-- The designation of a creature, ignoring quest status:
--   1. "critter" for a critter type (isCritter = true)
--   2. the designation in the creature list (a creature in the list with no
--      designation is "normal")
--   3. for a creature that is not in the list: what the game reported when
--      you met it (elite, rare, world boss)
--   4. "normal"
function ns.DesignationClass(db, npcID, isCritter)
  if isCritter then return "critter" end

  -- What the game itself showed when you met the creature wins over the list,
  -- so the Hunting Log corrects itself: a level of ?? is always a boss, and
  -- otherwise the game's elite / rare / world boss mark decides.
  local k = db.known and db.known[npcID]
  if type(k) == "table" then
    if ns.SeenAsBoss(k) then return "boss" end         -- level ?? at the top level is a boss
    if ns.USE_GAME_CLASSIFICATION and k.uclass then
      return AUTO_CLASS[k.uclass] or "normal"          -- (normal, trivial, minor creatures are "normal")
    end
  end

  -- Otherwise the creature list. A level of ?? always means a boss.
  local row = ns.SeedRow(npcID)
  if row then
    if row.level == "??" then return "boss" end
    return row.class or "normal"
  end
  return "normal"
end

-- The class a creature has before any choice of yours: a critter type, else
-- the default in ClassData.lua (quest creatures), else its designation.
function ns.BaseClass(db, npcID, isCritter)
  if isCritter then return "critter" end
  local baked = ns.SeedClass and ns.SeedClass[npcID]   -- defaults saved in ClassData.lua
  if baked then return baked end
  return ns.DesignationClass(db, npcID, isCritter)
end

-- The creature's class: your saved choice if you made one, else its base class.
function ns.GetClass(db, npcID, isCritter)
  local chosen = db.classes and db.classes[npcID]
  if chosen then return chosen end
  return ns.BaseClass(db, npcID, isCritter)
end

-- Saves a class exactly as given (kept for old code; the menu uses
-- SetDesignation and SetQuest below).
function ns.SetClass(npcID, class)
  local db = ns.DB()
  db.classes = db.classes or {}
  db.classes[npcID] = class
end

-- You change a creature's designation. If your choice is the same as what it
-- would be anyway, the saved choice is removed, so db.classes only ever holds
-- real changes (they can be reviewed with Show > Changed by you).
function ns.SetDesignation(npcID, class, isCritter)
  local db = ns.DB()
  db.classes = db.classes or {}
  if class == ns.BaseClass(db, npcID, isCritter) then
    db.classes[npcID] = nil
  else
    db.classes[npcID] = class
  end
end

-- You mark a creature as a quest creature (on = true), or take that away
-- (on = false, which returns it to its designation).
function ns.SetQuest(npcID, on, isCritter)
  local db = ns.DB()
  db.classes = db.classes or {}
  local base = ns.BaseClass(db, npcID, isCritter)
  if on then
    db.classes[npcID] = (base == "quest") and nil or "quest"
  else
    -- If the default itself says quest (ClassData.lua), say its designation instead
    db.classes[npcID] = (base == "quest") and ns.DesignationClass(db, npcID, isCritter) or nil
  end
end

-- Removes saved choices that are now the same as the default (for example a
-- class you set before the creature list gave it a designation). Called at login.
function ns.CleanClasses()
  local db = ns.DB()
  if not db.classes then return end

  -- Choices to forget outright, so these creatures go back to the creature list:
  --   Urs'anah (251115) was set to boss before the list existed; the list calls him normal.
  --   Captain Flat Tusk (5824) was set to elite; he is a rare elite, and rare elites stay rare.
  local FORGET = { 251115, 5824 }
  for _, id in ipairs(FORGET) do db.classes[id] = nil end

  for id, class in pairs(db.classes) do
    local crit = ns.IsCritterType(ns.CreatureCtype(db, id))
    if class == ns.BaseClass(db, id, crit) then db.classes[id] = nil end
  end
end

-- Does a row of the creature list belong in the log of this faction ("A" or
-- "H")? Rows carry A and H fields (hostile / neutral toward each faction).
function ns.SeedHas(c, letter)
  return c[letter] ~= nil or (c.fac ~= nil and c.fac:find(letter, 1, true) ~= nil)
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


-- ===== TABS INSIDE A PAGE =====
-- Pages listed in ns.SUBTABS (PageEvents.lua) show tab buttons above their
-- text. Returns the key of the tab selected for a page (the first tab until
-- you pick another), or nil if the page has no tabs.
function ns.GetSubTab(page)
  local tabs = ns.SUBTABS and ns.SUBTABS[page]
  if not tabs then return nil end
  local chosen = ns.Settings().subtabs[page]
  for _, t in ipairs(tabs) do
    if t.key == chosen then return chosen end
  end
  return tabs[1].key
end


-- ===== DROP RATES =====
-- Text like "3/12 (25.0%)" for an item (or coin) that dropped `drops` times
-- in `kills` kills.
function ns.RateText(drops, kills)
  local n = math.max(kills, 1)   -- avoid dividing by zero
  return string.format("%d/%d (%.1f%%)", drops, n, 100 * drops / n)
end


-- ===== DATES =====
-- A time (as saved by time()) as text, for example 2026-10-03.
function ns.DateText(t)
  return date("%Y-%m-%d", t)
end

-- A time as date and time, for example 2026-10-03 22:58 (your computer's clock).
function ns.DateTimeText(t)
  return date("%Y-%m-%d %H:%M", t)
end


-- ===== ITEM RARITY =====
-- Item quality numbers: 0 poor (grey), 1 common (white), 2 uncommon (green),
-- 3 rare (blue), 4 epic (purple) and above.

-- The quality of an item, read from its saved link. The game writes the
-- colour into the link ("|cnIQ2:" on this client, or a plain colour code on
-- older ones). Falls back to the game's own data. Returns nil if unknown.
function ns.ItemQuality(db, itemID)
  local link = db.items and db.items[itemID]
  if link then
    local q = link:match("|cnIQ(%d+):")
    if q then return tonumber(q) end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex then
      local byColor = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }
      local known = byColor[hex:lower()]
      if known then return known end
    end
  end
  if C_Item and C_Item.GetItemQualityByID then
    local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
    if ok and type(q) == "number" then return q end
  end
  return nil
end

-- Does a quality fit the rarity filter? key is "all", "poor", "common",
-- "uncommon", "rare" or "epic" (epic and above). An unknown quality only
-- passes "all".
function ns.RarityMatches(key, quality)
  if key == "all" then return true end
  if quality == nil then return false end
  if key == "poor" then return quality == 0 end
  if key == "common" then return quality == 1 end
  if key == "uncommon" then return quality == 2 end
  if key == "rare" then return quality == 3 end
  if key == "epic" then return quality >= 4 end
  return true
end

-- Choices for the rarity drop-down. label is the menu text, short is what
-- the button shows. The |cffRRGGBB ... |r parts colour the text.
ns.RARITY_CHOICES = {
  { key = "all",      label = "All",                                  short = "All" },
  { key = "poor",     label = "|cff9d9d9dPoor (grey)|r",              short = "|cff9d9d9dGrey|r" },
  { key = "common",   label = "|cffffffffCommon (white)|r",           short = "|cffffffffWhite|r" },
  { key = "uncommon", label = "|cff1eff00Uncommon (green)|r",         short = "|cff1eff00Green|r" },
  { key = "rare",     label = "|cff0070ddRare (blue)|r",              short = "|cff0070ddBlue|r" },
  { key = "epic",     label = "|cffa335eeEpic or higher|r",           short = "|cffa335eeEpic+|r" },
}

-- ===== DELETING A CREATURE'S DATA =====
-- Removes a creature from the Mob Drops data: its kills, drops and coin.
-- (Overall coin totals and the Hunting Log's "seen" record are kept; the
-- creature simply returns to 0 kills.)
function ns.DeleteMob(npcID)
  local db = ns.DB()
  db.mobs[npcID] = nil
  if ns.selectedMob == npcID then ns.selectedMob = nil end
  if ns.Refresh then ns.Refresh() end
end


-- ===== STARS (shared by the Hunting Log and the chat messages) =====

-- How many stars a creature has earned (0 to 3), for its class and kill count.
-- seen = true if you have met the creature (critters earn a star for that).
function ns.StarsFor(kills, class, seen)
  local n = 0
  if class == "critter" and seen then n = 1 end   -- first critter star = seeing it
  for _, tier in ipairs(ns.TiersFor(class)) do
    if kills >= tier then n = n + 1 end
  end
  return n
end

-- How many stars are possible for a class: 3 for most, 1 for quest creatures.
-- (A critter's first star is for seeing it, so it has one more than its tiers.)
function ns.MaxStars(class)
  local n = #ns.TiersFor(class)
  if class == "critter" then n = n + 1 end
  return math.min(n, 3)
end

-- ===== LOOKING UP WHAT WE KNOW ABOUT A CREATURE =====
local seedById   -- creature ID -> its row in the starter lists, built the first time it is needed

-- The starter-list row for a creature ID, or nil.
function ns.SeedRow(npcID)
  if not seedById then
    seedById = {}
    for _, c in ipairs(ns.SeedCreatures or {}) do
      if not seedById[c.id] then seedById[c.id] = c end
    end
  end
  return seedById[npcID]
end

-- The creature type ("Beast", "Critter"...): what the game told us when you
-- met it, else the starter list.
function ns.CreatureCtype(db, npcID)
  local k = db.known and db.known[npcID]
  if type(k) == "table" and k.ctype then return k.ctype end
  local row = ns.SeedRow(npcID)
  return row and row.ctype
end

-- ===== FISHING SECTIONS AND STARS (shared by the Fishing Log and the messages) =====
local fishListed   -- item ID -> its row in FishData.lua, built the first time it is needed

-- The FishData.lua row for an item ID, or nil if it is not in the list.
function ns.FishRow(itemID)
  if not fishListed then
    fishListed = {}
    for _, row in ipairs(ns.FishList or {}) do fishListed[row.id] = row end
  end
  return fishListed[itemID]
end

-- Which section an item belongs to (see the bottom of FishData.lua).
-- row is the item's FishData.lua row, or nil for an item not in the list.
function ns.FishSectionOfRow(row, itemID)
  if not row then
    -- Not in FishData.lua: sort it into an existing section if we can
    if itemID then return ns.ClassifyUnlistedFish(itemID) end
    return "Not in your list"
  end
  local override = ns.FISH_ITEM_SECTION and ns.FISH_ITEM_SECTION[row.id]   -- a single item placed by hand
  if override then return override end
  for _, rule in ipairs(ns.FISH_NAME_RULES or {}) do
    if row.name:find(rule.pattern) then return rule.section end
  end
  return (ns.FISH_SECTION_OF and ns.FISH_SECTION_OF[row.type]) or "Other"
end

-- The catches needed for each star of an item, and its section name.
function ns.FishTiers(itemID)
  local section = ns.FishSectionOfRow(ns.FishRow(itemID), itemID)
  local tiers = (ns.FISH_STAR_TIERS and ns.FISH_STAR_TIERS[section]) or ns.FISH_STAR_DEFAULT or { 1 }
  return tiers, section
end

-- How many stars a catch total earns, given the tiers from ns.FishTiers.
function ns.FishStarCount(tiers, total)
  local n = 0
  for _, tier in ipairs(tiers) do
    if total >= tier then n = n + 1 end
  end
  return n
end

-- How many of an item you have caught, in all zones added together.
function ns.FishTotal(db, itemID)
  local total = 0
  for _, items in pairs((db.events and db.events["Fishing"]) or {}) do
    local e = items[itemID]
    if e then total = total + e.count end
  end
  return total
end


-- ===== VERSION =====
-- Read from the "## Version:" line of LootLog.toc, so there is one place to
-- change it. Shown on the Help page.
ns.VERSION = "unknown"
pcall(function()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    v = C_AddOns.GetAddOnMetadata("LootLog", "Version")
  elseif GetAddOnMetadata then
    v = GetAddOnMetadata("LootLog", "Version")
  end
  if type(v) == "string" and v ~= "" then ns.VERSION = v end
end)

-- ===== THIS SESSION =====
-- Totals since you logged in or reloaded (not saved). Filled in by Capture.lua,
-- shown on the Session page.
ns.session = {
  start = GetTime(),   -- when the session began (game clock, for the length)
  startTime = time(),  -- when it began (real clock, for the date)
  kills = 0,
  coin = 0,            -- copper
  items = 0,           -- items looted (counting stack sizes)
  itemQty = {},        -- itemID -> how many
  byQuality = {},      -- item quality (0 grey ... 5 legendary) -> how many
  mobKills = {},       -- creature name -> kills
}


-- ===== SAVING THE LAST SESSION =====
-- A summary of this session so far, in the shape that is saved and shown:
-- totals, items by quality, and the 10 most killed creatures and most looted
-- items (as lists, biggest first).
function ns.SessionSnapshot()
  local sess = ns.session
  local who, loot = {}, {}
  for name, n in pairs(sess.mobKills) do who[#who + 1] = { name = name, n = n } end
  table.sort(who, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.name < b.name
  end)
  for itemID, n in pairs(sess.itemQty) do loot[#loot + 1] = { id = itemID, n = n } end
  table.sort(loot, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.id < b.id
  end)
  local function top(list)
    local out = {}
    for i = 1, math.min(#list, 10) do out[i] = list[i] end
    return out
  end
  local byQuality = {}
  for q, n in pairs(sess.byQuality) do byQuality[q] = n end
  return {
    startTime = sess.startTime,
    endTime = time(),
    seconds = GetTime() - sess.start,
    kills = sess.kills, coin = sess.coin, items = sess.items,
    byQuality = byQuality,
    mobs = top(who), loot = top(loot),
  }
end

-- Keeps this session as the character's "previous session" for next time.
-- Called when you log out or reload. A session with nothing in it is not
-- kept, so a quick reload does not wipe out the last real one.
function ns.SaveSession()
  local sess = ns.session
  if sess.kills == 0 and sess.items == 0 and sess.coin == 0 then return end
  CharData().lastSession = ns.SessionSnapshot()
end


-- ===== QUEST ITEMS =====
-- Items that belong to quests are listed apart from ordinary drops. An item
-- counts as a quest item if the loot window said so when it dropped
-- (saved in the shared db.questItems) or the game's item data puts it in the
-- Quest item class.
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local questClassCache = {}   -- itemID -> true / false, so the game is asked once

function ns.IsQuestItem(db, itemID)
  if db.questItems and db.questItems[itemID] then return true end
  local cached = questClassCache[itemID]
  if cached == nil then
    cached = false
    pcall(function()
      if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)   -- (6th value is the item class)
        cached = (classID == QUEST_CLASS)
      end
    end)
    questClassCache[itemID] = cached
  end
  return cached
end

-- Splits a list of drops (each with an .id) into ordinary items and quest
-- items. Returns two lists; the order inside each is kept.
function ns.SplitQuestItems(db, drops)
  local regular, quest = {}, {}
  for _, d in ipairs(drops) do
    if ns.IsQuestItem(db, d.id) then quest[#quest + 1] = d else regular[#regular + 1] = d end
  end
  return regular, quest
end


-- ===== WHERE THE GAME DISAGREES WITH THE CREATURE LIST =====
-- Compares what the game showed you (db.known) with the creature list
-- (Seed_Creatures.lua): name, type, designation, level, and how each faction
-- is treated. Returns a sorted list of text lines, one per creature that
-- differs. The Hunting Log already goes by the game in these cases; this just
-- lets you see where it happened.
function ns.Corrections(db)
  local out = {}
  for id in pairs(db.known or {}) do
    local k = ns.GetKnown(db, id)
    local row = ns.SeedRow(id)
    if k and row then
      local diffs = {}
      if k.name and k.name ~= row.name then
        diffs[#diffs + 1] = "name (list: " .. row.name .. ")"
      end
      -- ("Not specified" is the game's wording for the list's "Uncategorized")
      if k.ctype and row.ctype and k.ctype ~= row.ctype
         and not (k.ctype == "Not specified" and row.ctype == "Uncategorized") then
        diffs[#diffs + 1] = "type " .. k.ctype .. " (list: " .. row.ctype .. ")"
      end

      -- Designation. A level of ?? always means a boss.
      local listClass = (row.level == "??") and "boss" or (row.class or "normal")
      local seenClass
      if ns.SeenAsBoss(k) then seenClass = "boss"
      elseif k.uclass then seenClass = AUTO_CLASS[k.uclass] or "normal" end
      if seenClass and not ns.IsCritterType(k.ctype or row.ctype) and seenClass ~= listClass then
        diffs[#diffs + 1] = "designation " .. seenClass .. " (list: " .. listClass .. ")"
      end

      -- Level: a single number, a range like "34 - 35", or ??
      -- (a ?? seen below the top level says nothing: creatures far above your level show ?? too)
      if type(k.level) == "number" and (k.level >= 0 or ns.SeenAsBoss(k)) and row.level and row.level ~= "" then
        local lo, hi = row.level:match("^(%d+)%s*%-%s*(%d+)$")
        if not lo then lo = row.level:match("^(%d+)$"); hi = lo end
        if row.level == "??" then
          if k.level ~= -1 then diffs[#diffs + 1] = "level " .. k.level .. " (list: ??)" end
        elseif k.level == -1 then
          diffs[#diffs + 1] = "level ?? (list: " .. row.level .. ")"
        elseif lo and (k.level < tonumber(lo) or k.level > tonumber(hi)) then
          diffs[#diffs + 1] = "level " .. k.level .. " (list: " .. row.level .. ")"
        end
      end

      -- Hostility toward each faction
      for _, letter in ipairs({ "A", "H" }) do
        local seen, listed = k.host and k.host[letter], row[letter]
        if seen and listed and seen ~= listed then
          diffs[#diffs + 1] = (letter == "A" and "Alliance " or "Horde ") .. seen .. " (list: " .. listed .. ")"
        end
      end

      if #diffs > 0 then
        out[#out + 1] = (k.name or row.name) .. " (" .. id .. "): " .. table.concat(diffs, ", ")
      end
    end
  end
  table.sort(out)
  return out
end


-- ===== THE ?? LEVEL =====
-- The creature list says a creature with level ?? is a boss. In the game, ?? also
-- shows for any creature far above YOUR level, so a ?? seen in game only counts
-- once you are at the top level.
ns.MAX_LEVEL = 60

-- Did the game show this creature (k = its db.known record) as level ?? to
-- someone at the top level? (k.level is -1 for ??, k.lvlBy is the player's level.)
function ns.SeenAsBoss(k)
  return type(k) == "table" and k.level == -1 and (k.lvlBy or 0) >= ns.MAX_LEVEL
end

-- ===== SORTING A NEW FISHING CATCH INTO AN EXISTING SECTION =====
-- For an item that is not in FishData.lua: use the game's own item information
-- (its class and sub-class, and its name) to pick one of the sections that
-- already exist. "Not in your list" is only used when the game gives us nothing.
local FISHY_WORDS = { "fish", "eel", "squid", "snapper", "grouper", "bass", "trout", "salmon",
                      "catfish", "blackmouth", "sturgeon", "mackerel", "tuna" }
local CONTAINER_WORDS = { "clam", "crate", "chest", "lockbox", "footlocker", "satchel", "strongbox", "barrel", "cache" }

local function NameHas(name, words)
  if not name then return false end
  name = name:lower()
  for _, w in ipairs(words) do
    if name:find(w, 1, true) then return true end
  end
  return false
end

function ns.ClassifyUnlistedFish(itemID)
  local db = ns.DB()
  local link = db.items and db.items[itemID]
  local name = link and link:match("%[(.-)%]") or nil
  if not name then
    pcall(function() name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or GetItemInfo(itemID) end)
  end
  if name and name:find("^%d+ Pound ") then return "Big fish" end
  if ns.IsQuestItem(db, itemID) then return "Quest fish and items" end

  local classID, subID
  pcall(function()
    if C_Item and C_Item.GetItemInfoInstant then
      local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(itemID)
      classID, subID = c, s
    end
  end)
  if not classID then return "Not in your list" end       -- the game gave us nothing to go by

  if classID == 2 or classID == 4 then return "Gear" end  -- weapons and armor
  if classID == 1 then return "Containers and bags" end
  if classID == 0 then                                    -- consumables
    if subID == 1 or subID == 2 or subID == 3 or subID == 4 then return "Potions and scrolls" end
    return "Food, drink and reagents"
  end
  if classID == 5 then return "Food, drink and reagents" end
  if classID == 7 then                                    -- trade goods
    if subID == 8 then                                    -- "Meat": a fish, or food
      return NameHas(name, FISHY_WORDS) and "Fish" or "Food, drink and reagents"
    end
    return "Materials"
  end
  if classID == 9 then return "Recipes and patterns" end
  if classID == 12 then return "Quest fish and items" end
  if classID == 15 then                                   -- miscellaneous
    if subID == 0 then return "Junk" end
    if NameHas(name, CONTAINER_WORDS) then return "Containers and bags" end
    return "Other"
  end
  return "Other"
end

-- ===== WHAT YOU SOLD, BY ITEM =====
-- db.sales[itemID] = { vendorCount, vendorGold, aucCount, aucGold }: how many
-- of an item you sold to vendors and at the auction house, and for how much
-- (copper). Written by Capture.lua. Returns the record or nil, plus the
-- combined gold and count.
function ns.SaleTotals(db, itemID)
  local s = db.sales and db.sales[itemID]
  if not s then return nil, 0, 0 end
  return s, (s.vendorGold or 0) + (s.aucGold or 0), (s.vendorCount or 0) + (s.aucCount or 0)
end

-- ===== ONE-TIME CLEAN-UP OF QUEST REWARDS LOGGED AS RECEIVED ITEMS =====
-- Before quest rewards were kept out of the Received Items tabs, some were
-- logged there too. This takes them out once, using the Quest Rewards log.
function ns.CleanReceived()
  local db = ns.DB()
  if db.cleanedQuestRewards then return end
  db.cleanedQuestRewards = true
  local other, quest = db.events["Other received"], db.events["Quest"]
  if not other or not quest then return end
  for zone, items in pairs(quest) do
    local oz = other[zone]
    if oz then
      for itemID, qe in pairs(items) do
        local oe = oz[itemID]
        if oe then
          oe.count = oe.count - qe.count
          if oe.count <= 0 then oz[itemID] = nil end
        end
      end
    end
  end
end
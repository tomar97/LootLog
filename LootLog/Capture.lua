--[[
=====================================================================
 Capture.lua - reads the loot window and writes into the database
=====================================================================
 It also notices kills that never open a loot window (see KILL DETECTION).
 To add a new capture source later (gold, quest rewards, mail), either
 extend the handler below or create a new Capture file and add it to
 the .toc after Core.lua.
=====================================================================
]]

local ADDON, ns = ...

-- Local shortcuts to the shared tables defined in Core.lua.
-- These point at the SAME tables, so changes are shared.
local seen, counted, names = ns.seen, ns.counted, ns.names
local ITEM_SLOT = ns.ITEM_SLOT


-- ===== MOB NAME CACHE =====
-- A loot window gives us a GUID but no mob name. A GUID looks like:
--   "Creature-0-1234-5678-9012-12345-0000ABCDEF"
-- strsplit("-") breaks it apart. The 6th piece (id) is the mob's NPC ID.
-- Names are learned when you target or mouse over a mob.
local function CacheName(unit)
  local guid = UnitGUID(unit)
  if not guid then return end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" then
    local npcID = tonumber(id)
    local name = UnitName(unit)
    names[npcID] = name
    -- Hunting Log: permanently remember hostile creatures you have seen.
    -- Skips players, friendly NPCs (vendors etc.), and player pets.
    -- Non-combat pets can't be attacked but belong on the Critters tab, so
    -- they are allowed through too.
    local ctype = UnitCreatureType(unit)
    local isPet = (ctype == "Non-combat Pet")
    if name and (UnitCanAttack("player", unit) or isPet)
       and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit) then
      local k = ns.TouchKnown(npcID, name)   -- find or create its record (Core.lua)
      -- Remember where it was seen: the zone, plus the sub-zone when that
      -- is also in the zone list (see ns.CurrentPlaces in Core.lua)
      for _, place in ipairs(ns.CurrentPlaces()) do
        k.zones = k.zones or {}
        k.zones[place] = true
      end
      -- Remember which faction's character saw it (Alliance / Horde log)
      local fac = ns.PlayerFaction()
      if fac then
        k.fac = k.fac or {}
        k.fac[fac] = true
        -- How your faction is treated: neutral (yellow) or hostile (red).
        -- Skipped while the creature is in combat, because a neutral
        -- creature you attack turns hostile and would be mislabeled.
        local reaction = UnitReaction("player", unit)
        if reaction and not UnitAffectingCombat(unit) then
          k.host = k.host or {}
          if reaction <= 3 then
            k.host[fac] = "hostile"
          elseif reaction == 4 then
            k.host[fac] = "neutral"
          end
        end
      end
      -- Creature type (Beast, Critter...) and the game's own classification
      -- (elite, rare, worldboss...). The classification gives a default
      -- Elite / Rare / Boss tag; see ns.GetClass in Core.lua.
      k.ctype = ctype or k.ctype
      k.uclass = UnitClassification(unit) or k.uclass
    end
  end
end


-- =====================================================================
-- KILL DETECTION WITHOUT A LOOT WINDOW
-- =====================================================================
-- Counting kills only when a loot window opens misses creatures that drop
-- nothing, and quest creatures. The combat log is BLOCKED for addons on this
-- client, so we use what is left:
--   UNIT_DIED   fires when a creature dies nearby and includes its GUID.
--               It also fires for OTHER players' kills, so it is not enough
--               on its own.
--   Your target we watch your target while you fight it. A creature counts
--               as YOUR kill only if you were fighting it (targeted, in
--               combat, not tagged by someone else) shortly before it died.
-- Whichever signal arrives first records the kill; ns.seen (Core.lua)
-- stops the same corpse being counted twice, including when you loot it.
--
-- Not counted: kills you never targeted (pets, area damage on untargeted
-- creatures) and creatures other players tagged.
--
-- /lootlog kills turns on messages that show what this code decides.

local issecret = issecretvalue or function() return false end   -- "secret" values cannot be read
local ENGAGED_WINDOW = 30   -- seconds a creature stays "yours" after you last fought it
local engaged = {}          -- creature GUID -> time you were last fighting it

-- Calls an API function safely. Returns its value, or nil when it fails or
-- the value is secret (unreadable). A nil answer means "unknown".
local function read(fn, ...)
  local ok, v = pcall(fn, ...)
  if not ok or issecret(v) then return nil end
  return v
end

-- Prints only when /lootlog kills is on.
local function kdebug(...)
  if ns.killDebug then print("|cff66ccffKills|r", ...) end
end

-- Adds one kill for the creature with this GUID. Does nothing if that corpse
-- was already counted, or if the GUID is not a creature.
local function RecordKill(guid, zone)
  if seen[guid] then return end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" then return end
  seen[guid] = true
  zone = zone or GetRealZoneText() or "Unknown"
  local db = ns.DB()
  local npcID = tonumber(id)
  local m = db.mobs[npcID] or { name = names[npcID], kills = 0, items = {} }
  m.name = m.name or names[npcID]
  m.zone = zone
  ns.CountKill(m, zone)   -- adds 1 to m.kills AND to m.zones[zone]
  db.mobs[npcID] = m
end

-- A creature has died (or its death was noticed). Count it if it was yours.
local function KillFor(guid, how)
  if type(guid) ~= "string" or issecret(guid) or not guid:find("^Creature") then return end
  local t = engaged[guid]
  if not t or (GetTime() - t) > ENGAGED_WINDOW then
    kdebug(how, "ignored (you were not fighting it):", guid)
    return
  end
  engaged[guid] = nil
  if seen[guid] then return end   -- already counted (for example from its loot)
  RecordKill(guid)
  kdebug(how, "-> kill counted:", guid)
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end

-- Looks at your current target. If it is a creature you are fighting, mark
-- it as yours. If it is already dead and was yours, count the kill.
local function CheckTarget()
  if not UnitExists("target") then return end
  local guid = read(UnitGUID, "target")
  if type(guid) ~= "string" or not guid:find("^Creature") then return end

  if read(UnitIsDead, "target") == true then
    KillFor(guid, "target died")
    return
  end

  -- Alive: is it something you are fighting?
  if read(UnitCanAttack, "player", "target") == false then return end   -- friendly
  if read(UnitIsTapDenied, "target") == true then return end            -- tagged by someone else
  local inCombat = read(UnitAffectingCombat, "target")
  if inCombat == false then return end                                   -- not fighting
  if inCombat == nil and read(UnitAffectingCombat, "player") ~= true then return end   -- unknown: need YOU in combat

  if not engaged[guid] then
    kdebug("fighting:", read(UnitName, "target") or "?", guid,
           "| tapDenied:", tostring(read(UnitIsTapDenied, "target")),
           "| targetInCombat:", tostring(inCombat))
  end
  engaged[guid] = GetTime()
end

-- Forgets old entries so the table does not grow forever.
local function PruneEngaged()
  local now = GetTime()
  for g, t in pairs(engaged) do
    if now - t > 60 then engaged[g] = nil end
  end
end


-- =====================================================================
-- COIN (GOLD) CAPTURE
-- =====================================================================
-- A loot slot of type "money" has quantity 0; the amount is only in its text,
-- for example "5 copper" (tested on this client). So we read the text.
-- The game's own words for gold / silver / copper (GOLD_AMOUNT and friends,
-- like "%d Gold") are used, so this also works in other languages.

local MONEY_SLOT = ns.MONEY_SLOT

-- Escapes characters that mean something special in a Lua pattern.
local function EscapePattern(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Builds a pattern from a game format string. "%d Gold" becomes "([%d,%.]+) gold"
-- (lower case, because the slot text can differ in capital letters).
local function AmountPattern(fmt)
  local before, after = fmt:lower():match("^(.-)%%d(.*)$")
  if not before then return nil end
  return EscapePattern(before) .. "([%d,%.]+)" .. EscapePattern(after)
end

local COIN_UNITS = {
  { AmountPattern(GOLD_AMOUNT   or "%d Gold"),   10000 },
  { AmountPattern(SILVER_AMOUNT or "%d Silver"), 100 },
  { AmountPattern(COPPER_AMOUNT or "%d Copper"), 1 },
}

-- Reads an amount in copper out of slot text like "1 silver 5 copper".
-- Returns 0 if nothing could be read.
local function ParseMoney(text)
  if type(text) ~= "string" then return 0 end
  text = text:lower()
  local total = 0
  for _, unit in ipairs(COIN_UNITS) do
    local pattern, worth = unit[1], unit[2]
    if pattern then
      local digits = text:match(pattern)
      if digits then
        -- remove thousands separators such as the comma in "1,234"
        local n = tonumber((digits:gsub("[^%d]", "")))
        if n then total = total + n * worth end
      end
    end
  end
  return total
end

-- Records one coin slot. amount is the whole slot in copper. The coin can
-- come from several corpses at once (area loot), so it is split between them.
local function LogCoin(slot, amount, zone, fishing)
  local db = ns.DB()
  local src = { GetLootSourceInfo(slot) }   -- guid1, qty1, guid2, qty2, ...
  local sources = {}
  for i = 1, #src, 2 do sources[#sources + 1] = { guid = src[i], qty = src[i + 1] } end
  if #sources == 0 then return end          -- nothing to credit it to

  -- How much each source gets: all of it for one source; the quantities the
  -- game gives if they add up to the total; otherwise an even split.
  local sum = 0
  for _, s in ipairs(sources) do sum = sum + (s.qty or 0) end
  local share = {}
  for i, s in ipairs(sources) do
    if #sources == 1 then
      share[i] = amount
    elseif sum == amount then
      share[i] = s.qty
    else
      share[i] = math.floor(amount / #sources) + ((i == 1) and (amount % #sources) or 0)
    end
  end

  for i, s in ipairs(sources) do
    local guid = s.guid
    local key = guid .. ":coin"
    if not counted[key] then              -- same guard as items: reopening a corpse must not add it twice
      counted[key] = true
      local kind, _, _, _, _, id = strsplit("-", guid)
      local category = fishing and "Fishing"
        or (kind == "Creature" and "Mobs")
        or (kind == "GameObject" and "Objects") or "Other"
      local coin = share[i]

      -- Overall totals, by source and zone
      db.gold = db.gold or {}
      db.gold.total = (db.gold.total or 0) + coin
      db.gold.drops = (db.gold.drops or 0) + 1
      db.gold.events = db.gold.events or {}
      local byZone = db.gold.events[category]
      if not byZone then byZone = {}; db.gold.events[category] = byZone end
      byZone[zone] = (byZone[zone] or 0) + coin

      -- Per creature: total coin and how many corpses dropped coin
      if kind == "Creature" then
        local m = db.mobs[tonumber(id)]
        if m then
          m.gold = (m.gold or 0) + coin
          m.goldDrops = (m.goldDrops or 0) + 1
        end
      end
      kdebug("coin counted:", ns.FormatMoney(coin), "from", category)
    end
  end
end


-- ===== EVENT REGISTRATION =====
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_TARGET_CHANGED")   -- you changed target (name cache)
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")   -- you moused over a unit (name cache)
f:RegisterEvent("LOOT_OPENED")             -- loot window opened (auto loot off)
f:RegisterEvent("LOOT_READY")              -- loot available (needed for auto loot)
-- Events that mean "you may be somewhere new" (records visited places, which
-- decides which starter creatures load in the Hunting Log)
f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- login, reload, or loading screen
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")   -- entered a new zone
f:RegisterEvent("ZONE_CHANGED")            -- entered a new sub-zone
f:RegisterEvent("ZONE_CHANGED_INDOORS")    -- entered a sub-zone indoors
-- Kill detection (see KILL DETECTION above). The combat log is blocked, so
-- these are the signals we can use. pcall = ignore the error if the client
-- refuses an event.
pcall(f.RegisterEvent, f, "UNIT_DIED")                   -- a creature died nearby (GUID in the event)
pcall(f.RegisterUnitEvent, f, "UNIT_HEALTH", "target")   -- your target's health changed (target only)
f:RegisterEvent("PLAYER_REGEN_DISABLED")   -- you entered combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")    -- you left combat
-- Both loot events can fire for the same corpse. The "seen" and "counted"
-- tables make sure it is only logged once.

f:SetScript("OnEvent", function(_, event, arg1)
  -- Name-cache events (and the target check) do their job and stop.
  if event == "PLAYER_TARGET_CHANGED" then
    CacheName("target")
    CheckTarget()   -- also marks it as yours if you are fighting it
    return
  end
  if event == "UPDATE_MOUSEOVER_UNIT" then return CacheName("mouseover") end

  -- Kill detection events: stop after handling.
  if event == "UNIT_DIED" then return KillFor(arg1, "UNIT_DIED") end
  if event == "UNIT_HEALTH" or event == "PLAYER_REGEN_DISABLED" then return CheckTarget() end
  if event == "PLAYER_REGEN_ENABLED" then
    CheckTarget()
    PruneEngaged()
    return
  end

  -- Zone events: remember the place, redraw if the window is open, and stop.
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
     or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    ns.NoteVisited()
    if ns.RefreshIfOpen then ns.RefreshIfOpen() end
    return
  end

  -- Everything below runs for LOOT_OPENED / LOOT_READY.
  local db = ns.DB()
  local zone = GetRealZoneText() or "Unknown"
  local fishing = IsFishingLoot()   -- true if this loot came from fishing

  -- ---- STEP 1: count every looted corpse as a kill ----
  -- This runs before the item loop so a corpse that dropped only coin
  -- (no items) still counts as a kill. Without it, kills would be
  -- undercounted and drop percentages would come out too high.
  -- Fishing loot is skipped because a bobber is not a kill.
  if not fishing then
    for slot = 1, GetNumLootItems() do
      -- GetLootSourceInfo returns: guid1, qty1, guid2, qty2, ...
      -- (several guids appear when you loot multiple corpses at once)
      local src = { GetLootSourceInfo(slot) }
      for i = 1, #src, 2 do
        local guid = src[i]
        local kind, _, _, _, _, id = strsplit("-", guid)
        if kind == "Creature" then
          RecordKill(guid, zone)   -- does nothing if this corpse was already counted
        end
      end
    end
  end

  -- ---- STEP 2: log each item in the loot window ----
  for slot = 1, GetNumLootItems() do
    -- Only item slots. Money and currency slots are skipped for now.
    if GetLootSlotType(slot) == ITEM_SLOT then
      local link = GetLootSlotLink(slot)
      local icon, name, qty, _, quality = GetLootSlotInfo(slot)
      -- Pull the item ID out of the link text ("...|Hitem:12345:...|h...")
      local itemID = link and tonumber(link:match("item:(%d+)"))
      if itemID then
        -- Save the link and icon so the UI can show names and icons later
        db.items = db.items or {}
        db.items[itemID] = link
        db.icons = db.icons or {}
        db.icons[itemID] = icon

        -- One item slot can come from several corpses (area loot), so loop
        -- over every source. src = { guid1, qty1, guid2, qty2, ... }
        local src = { GetLootSourceInfo(slot) }
        for i = 1, #src, 2 do
          local guid = src[i]
          local kind, _, _, _, _, id = strsplit("-", guid)

          -- Decide which log category this loot belongs to.
          -- Add new categories (quest, mail...) by extending this check.
          local category = fishing and "Fishing"
            or (kind == "Creature" and "Mobs")
            or (kind == "GameObject" and "Objects") or "Other"

          -- Duplicate guard: skip if this corpse+item was already logged.
          -- Without it, reopening a corpse you didn't empty would add the
          -- same item again.
          local key = guid .. ":" .. itemID
          local isNew = not counted[key]
          counted[key] = true
          local amount = src[i + 1] or qty or 1   -- quantity from this source

          -- Event log: category -> zone -> item. Used by the Fishing and
          -- Gathering pages. Only on first sight of this corpse+item.
          if isNew then
            local z = db.events[category]; if not z then z = {}; db.events[category] = z end
            local zz = z[zone]; if not zz then zz = {}; z[zone] = zz end
            local e = zz[itemID] or { name = name, quality = quality, count = 0 }
            e.count = e.count + amount
            zz[itemID] = e
          end

          -- Per-mob stats: only for creatures. Used by the Mob Drops page.
          if kind == "Creature" then
            local npcID = tonumber(id)
            local m = db.mobs[npcID] or { name = names[npcID], kills = 0, items = {} }
            m.name = m.name or names[npcID]
            m.zone = zone
            -- This kill check is now redundant with STEP 1 but harmless.
            -- Left in as a safety net.
            if not seen[guid] then seen[guid] = true; ns.CountKill(m, zone) end
            if isNew then
              local it = m.items[itemID] or { drops = 0, qty = 0 }
              it.drops = it.drops + 1       -- dropped once more (for drop rate)
              it.qty = it.qty + amount      -- total items received
              m.items[itemID] = it
            end
            db.mobs[npcID] = m
          end
        end
      end
    end
  end

  -- ---- STEP 3: log coin ----
  -- Runs after the kill is counted in STEP 1, so the creature's record exists.
  for slot = 1, GetNumLootItems() do
    if GetLootSlotType(slot) == MONEY_SLOT then
      local _, text = GetLootSlotInfo(slot)   -- the coin slot's text, for example "5 copper"
      local amount = ParseMoney(text)
      if amount > 0 then
        LogCoin(slot, amount, zone, fishing)
      else
        kdebug("could not read a coin amount from:", tostring(text))
      end
    end
  end

  -- Redraw the window if it is open, once per loot (not once per slot).
  -- ns.RefreshIfOpen is defined in UI.lua, which loads after this file.
  -- That is fine because it is looked up when the event fires, not when
  -- this file loads. The "if" guards against it not existing yet.
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end)
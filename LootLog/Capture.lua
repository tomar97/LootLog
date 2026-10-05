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


-- Redraws the window soon (at most every half second) if it is open. Used
-- when new information arrives while you play, so an open Hunting Log keeps up.
local refreshPending = false
function ns.RequestRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0.5, function()
    refreshPending = false
    if ns.RefreshIfOpen then ns.RefreshIfOpen() end
  end)
end


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
      local firstSight = not (ns.DB().known and ns.GetKnown(ns.DB(), npcID))
      local k = ns.TouchKnown(npcID, name)   -- find or create its record (Core.lua)
      if firstSight then
        ns.RequestRefresh()                        -- an open Hunting Log drops its "Unseen" tag
        if ns.AnnounceSeen then ns.AnnounceSeen(npcID, name, ctype) end   -- a critter's first star (Messages.lua)
      end
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
      k.lastSeen = time()   -- when you last pointed at or targeted it (the Hunting Log's "Most recently seen" sort)
      -- The level the game shows (-1 means ??). The Hunting Log goes by this over the list.
      -- A creature far above YOUR level shows ?? too, so a ?? only counts once you
      -- are at the top level; below that it says nothing and the old level stays.
      local lvl, mine = UnitLevel(unit), UnitLevel("player")
      if type(lvl) == "number" and type(mine) == "number"
         and not (issecretvalue and (issecretvalue(lvl) or issecretvalue(mine))) then
        if lvl >= 0 then
          k.level = lvl
          k.lvlBy = mine
        elseif mine >= ns.MAX_LEVEL then
          k.level = -1
          k.lvlBy = mine
        end
      end
      local newClass = UnitClassification(unit)
      if newClass and newClass ~= k.uclass then
        k.uclass = newClass
        ns.RequestRefresh()   -- an open Hunting Log shows the new Elite / Rare / Boss tag right away
      end
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
  -- Had you met it before this kill? (decides whether a critter's "seen" star is new)
  local seenBefore = m.kills > 0 or (db.known ~= nil and db.known[npcID] ~= nil)
  ns.CountKill(m, zone)   -- adds 1 to m.kills AND to m.zones[zone]
  db.mobs[npcID] = m
  -- Session totals (the Session page)
  local sess = ns.session
  sess.kills = sess.kills + 1
  local who = m.name or names[npcID] or ("ID " .. npcID)
  sess.mobKills[who] = (sess.mobKills[who] or 0) + 1
  -- A chat message if this kill earned a star (Messages.lua)
  if ns.AnnounceKill then ns.AnnounceKill(npcID, m.name or names[npcID], m.kills, seenBefore) end
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
-- WHERE LOOT CAME FROM: gathering, quests
-- =====================================================================
-- Loot windows alone cannot say WHY you got something. Two extra signals:
--   Gathering   UNIT_SPELLCAST_SENT tells us you cast Mining, Herb Gathering,
--               or Skinning. Loot that opens within a few seconds is filed
--               under that profession instead of "Objects" or "Mobs".
--   Quests      QUEST_TURNED_IN / QUEST_LOOT_RECEIVED, plus the chat line
--               "You receive item: ..." right after a turn-in as a backup.
-- /lootlog kills prints what these decide.

-- Escapes characters that mean something special in a Lua pattern.
local function EscapePattern(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local ctx = {
  gather = nil,     -- { kind = "Mining", time = when you cast it, used = false }
  questTime = 0,    -- when you last turned in a quest
  lastMoney = nil,  -- the money you carried at the last change (to see how much it rose)
  tradeClosed = 0,  -- when a trade window last closed
  visitGold = 0,    -- gold sold for during the current vendor visit
  vendor = false,   -- a vendor window is open
  vendorName = nil, -- the name of that vendor
  questOpen = false,  -- a quest reward window is open
  lastCast = nil,   -- your last spell: { name, target, time }
  tradePartner = nil, tradeSnap = nil,   -- who you are trading with, and what was in the window when both accepted
  mail = false,     -- the mailbox is open
  trade = false,    -- a trade window is open
  questID = nil,    -- which quest you last turned in
  questTitle = nil, -- its title, read when the reward window showed
}
local gatherGuid = {}    -- guid -> profession, so every part of one loot agrees
local gatherName = {}    -- guid -> name of what you cast the profession on (for example "Copper Vein")
local questLogged = {}   -- itemID -> when it was logged as a quest reward

-- Spell IDs of the gathering professions (all ranks). If a spell is not in
-- this list we also compare by NAME against the first rank of each.
local GATHER_BY_ID = {
  [2575] = "Mining",    [2576] = "Mining",    [3564] = "Mining",    [10248] = "Mining",
  [2366] = "Herbalism", [2368] = "Herbalism", [3570] = "Herbalism", [11993] = "Herbalism",
  [8613] = "Skinning",  [8617] = "Skinning",  [8618] = "Skinning",  [10768] = "Skinning",
}
local gatherByName   -- spell name -> profession, built the first time it is needed

-- The name of a spell, whichever way this client provides it.
local function SpellNameOf(id)
  local ok, name = pcall(function()
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then
      local info = GetSpellInfo(id)
      if type(info) == "table" then return info.name end
      return info
    end
  end)
  if ok and type(name) == "string" then return name end
end

-- Which gathering profession (if any) a spell ID belongs to.
local function GatherKind(spellID)
  if GATHER_BY_ID[spellID] then return GATHER_BY_ID[spellID] end
  if not gatherByName then
    gatherByName = {}
    for _, id in ipairs({ 2575, 2366, 8613 }) do
      local name = SpellNameOf(id)
      if name then gatherByName[name] = GATHER_BY_ID[id] end
    end
  end
  local name = SpellNameOf(spellID)
  return name and gatherByName[name] or nil
end

-- The log category for loot from one source (a corpse or an object).
--   fishing  -> "Fishing"
--   a profession you just used -> "Mining" / "Herbalism" / "Skinning"
--   otherwise -> "Mobs", "Objects" (chests and so on), or "Other"
local function CategoryFor(guid, kind, fishing)
  if fishing then return "Fishing" end
  local known = gatherGuid[guid]
  if known then return known end
  local g = ctx.gather
  if g and not g.used and (GetTime() - g.time) < 10 then
    -- Mining and herbs open an object (a node); skinning opens a corpse.
    local fits = (g.kind == "Skinning" and kind == "Creature")
              or (g.kind ~= "Skinning" and kind == "GameObject")
    if fits then
      gatherGuid[guid] = g.kind
      gatherName[guid] = g.target
      g.used = true
      kdebug("gathering:", g.kind, guid)
      return g.kind
    end
  end
  return (kind == "Creature" and "Mobs") or (kind == "GameObject" and "Objects") or "Other"
end

-- The name of the chest or other object you just opened: the last object you
-- pointed at (Tooltips.lua remembers it), or the target of your last cast.
local function RecentObjectName()
  local o = ns.lastObject
  if o and GetTime() - o.time < 15 then return o.name end
  local c = ctx.lastCast
  if c and c.target and GetTime() - c.time < 10 then return c.target end
end

-- Gathering is also logged per NODE: which vein, herb, skinned creature, or
-- chest the loot came from. db.gather[category][zone][nodeKey] =
--   { id = object or creature ID, kind, gathers = times, items = { [itemID] = qty } }
-- nodeKey is "o<objectID>" for objects and "c<npcID>" for creatures (skinning).
-- Names are saved in db.nodeNames[nodeKey]: the game tells us the name of what
-- a profession was cast on, which we remember against the node's ID.
local GATHER_NODE_CATEGORIES = { Mining = true, Herbalism = true, Skinning = true, Objects = true }

-- Finds (or creates) the record for the node this loot came from and counts
-- the gather once. Returns the record, or nil for loot that is not gathering.
local function NoteNode(guid, kind, id, category, zone)
  if not GATHER_NODE_CATEGORIES[category] then return nil end
  local objectID = tonumber(id)
  if not objectID then return nil end
  local db = ns.DB()
  local key = (kind == "Creature" and "c" or "o") .. objectID

  -- The name: what you cast the profession on, or a known creature name
  local name = gatherName[guid] or (kind == "Creature" and names[objectID]) or nil
  local guessed = false
  if not name and kind == "GameObject" then
    name = RecentObjectName()   -- a chest has no gathering spell: use what you pointed at
    guessed = true
  end
  if name then
    db.nodeNames = db.nodeNames or {}
    -- a guessed name never replaces one we already trust
    if not guessed or not db.nodeNames[key] then db.nodeNames[key] = name end
  end

  db.gather = db.gather or {}
  local byZone = db.gather[category]
  if not byZone then byZone = {}; db.gather[category] = byZone end
  local nodes = byZone[zone]
  if not nodes then nodes = {}; byZone[zone] = nodes end
  local n = nodes[key]
  if not n then n = { id = objectID, kind = kind, gathers = 0, items = {} }; nodes[key] = n end

  if not counted[guid .. ":node"] then   -- LOOT_OPENED and LOOT_READY both fire: count once
    counted[guid .. ":node"] = true
    n.gathers = n.gathers + 1
  end
  return n
end

-- Where a drop came from, in words, for the rare-drop message.
local function SourceText(category, id, guid)
  local npcID = tonumber(id)
  if category == "Mobs" or category == "Skinning" then
    local m = ns.DB().mobs[npcID]
    return names[npcID] or (m and m.name) or "a creature"
  elseif category == "Fishing" then
    return "the water"
  elseif category == "Mining" or category == "Herbalism" then
    return gatherName[guid] or "a node"
  elseif category == "Objects" then
    return "a container"
  end
  return "somewhere"
end

-- Adds coin (in copper) to the totals, by source and zone.
local function AddGold(category, zone, coin)
  ns.session.coin = ns.session.coin + coin   -- session total
  local db = ns.DB()
  db.gold = db.gold or {}
  db.gold.total = (db.gold.total or 0) + coin
  db.gold.drops = (db.gold.drops or 0) + 1
  db.gold.events = db.gold.events or {}
  local byZone = db.gold.events[category]
  if not byZone then byZone = {}; db.gold.events[category] = byZone end
  byZone[zone] = (byZone[zone] or 0) + coin
end

-- Adds an item to the event log (category -> zone -> item), the same place
-- loot-window items go. Used for items that never open a loot window.
local function LogEvent(category, itemID, qty, link, zone)
  local db = ns.DB()
  db.items = db.items or {}
  if link then db.items[itemID] = link end
  local z = db.events[category]; if not z then z = {}; db.events[category] = z end
  local zz = z[zone]; if not zz then zz = {}; z[zone] = zz end
  local e = zz[itemID] or { name = link and link:match("%[(.-)%]") or nil, count = 0 }
  e.count = e.count + (qty or 1)
  e.quality = e.quality or ns.ItemQuality(db, itemID)   -- read from the item link (Core.lua)
  zz[itemID] = e
end

-- The record of one vendor in one zone: db.vendors[zone][vendorName] =
-- { sold = copper you got from selling, soldTimes, bought = { [itemID] = quantity } }.
-- Created if needed.
local function VendorRecord(zone, name)
  local db = ns.DB()
  db.vendors = db.vendors or {}
  local z = db.vendors[zone]
  if not z then z = {}; db.vendors[zone] = z end
  local v = z[name]
  if not v then v = { sold = 0, soldTimes = 0, bought = {} }; z[name] = v end
  return v
end

-- Turns a game message format such as "You receive item: %s." into a pattern
-- that captures the item link (the game's own wording, so other languages work).
local function FormatToPattern(fmt)
  local p = EscapePattern(fmt)
  p = p:gsub("%%%%s", "(.+)")     -- the item link
  p = p:gsub("%%%%d", "(%%d+)")   -- a quantity
  return "^" .. p .. "$"
end
local RECEIVE_MULTI  = LOOT_ITEM_PUSHED_SELF_MULTIPLE and FormatToPattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE)
local RECEIVE_SINGLE = LOOT_ITEM_PUSHED_SELF and FormatToPattern(LOOT_ITEM_PUSHED_SELF)
local CREATE_MULTI   = LOOT_ITEM_CREATED_SELF_MULTIPLE and FormatToPattern(LOOT_ITEM_CREATED_SELF_MULTIPLE)
local CREATE_SINGLE  = LOOT_ITEM_CREATED_SELF and FormatToPattern(LOOT_ITEM_CREATED_SELF)

-- Reads one of your own item messages:
--   "You receive item: [Link]x3."   (a quest reward, a purchase, mail, a trade...)
--   "You create: [Link]."           (something you crafted)
-- Returns itemID, quantity, link, kind ("received" or "created"), or nil.
-- Items from a loot window say "You receive loot:" instead and are NOT read
-- here, because the loot window code already logs them.
local function ParseReceived(text)
  if type(text) ~= "string" or issecret(text) then return nil end
  local link, qty, kind
  if CREATE_MULTI then link, qty = text:match(CREATE_MULTI) end
  if not link and CREATE_SINGLE then link = text:match(CREATE_SINGLE) end
  if link then
    kind = "created"
  else
    if RECEIVE_MULTI then link, qty = text:match(RECEIVE_MULTI) end
    if not link and RECEIVE_SINGLE then link = text:match(RECEIVE_SINGLE) end
    kind = "received"
  end
  if not link then return nil end
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID then return nil end
  return itemID, tonumber(qty) or 1, link, kind
end

-- The saved record of a quest: db.quests[questID]. Created if needed.
local function QuestRecord(questID)
  local db = ns.DB()
  db.quests = db.quests or {}
  local q = db.quests[questID]
  if not q then q = { rewards = {} }; db.quests[questID] = q end
  q.rewards = q.rewards or {}
  return q
end

-- Records a quest reward item. Two signals can report the same item, so an
-- item logged in the last 5 seconds is not logged again. questID may be nil
-- (the chat backup), in which case the quest you last turned in is used.
local function LogQuestReward(itemID, qty, link, how, questID)
  local now = GetTime()
  if questLogged[itemID] and now - questLogged[itemID] < 5 then return end
  questLogged[itemID] = now
  LogEvent("Quest", itemID, qty, link, GetRealZoneText() or "Unknown")
  -- Also list it under the quest itself (Completed Quests tab)
  local qid = questID
  if type(qid) ~= "number" or issecret(qid) then qid = ctx.questID end
  if qid then
    local q = QuestRecord(qid)
    q.rewards[itemID] = (q.rewards[itemID] or 0) + (qty or 1)
  end
  kdebug("quest reward:", link or itemID, "x" .. tostring(qty or 1), "(" .. how .. ")")
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end

-- You turned in a quest. Every turn-in is logged, with or without a reward:
-- name, date, your level, XP, coin, zone. Coin is also added to the Gold page.
local function OnQuestTurnedIn(questID, xp, money)
  ctx.questTime = GetTime()
  if type(questID) ~= "number" or issecret(questID) then return end
  ctx.questID = questID

  local q = QuestRecord(questID)
  local title
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if ok and type(t) == "string" and not issecret(t) then title = t end
  end
  q.name = title or ctx.questTitle or q.name        -- the title read when the reward window showed is the backup
  q.count = (q.count or 0) + 1                      -- repeatable quests count up
  q.t = time()                                      -- when (latest turn-in)
  q.first = q.first or q.t
  q.level = UnitLevel("player")                     -- your level when you turned it in
  q.zone = GetRealZoneText() or "Unknown"
  if type(xp) == "number" and not issecret(xp) then q.xp = xp end
  ctx.questTitle = nil

  if type(money) == "number" and not issecret(money) and money > 0 then
    q.money = money
    AddGold("Quest", q.zone, money)
    kdebug("quest coin:", ns.FormatMoney(money))
  end
  kdebug("quest turned in:", q.name or questID, "| level", tostring(q.level), "| xp", tostring(q.xp))
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end

-- The quest reward window opened: remember the quest's title, as a backup
-- for when the turn-in event does not give us a name.
local function OnQuestComplete()
  ctx.questOpen = true   -- items that arrive while this window is open are quest rewards
  local ok, title = pcall(GetTitleText)
  if ok and type(title) == "string" and not issecret(title) then ctx.questTitle = title end
end

-- The game reports a quest reward item.
local function OnQuestLoot(questID, link, qty)
  if type(link) ~= "string" or issecret(link) then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if itemID then
    LogQuestReward(itemID, (type(qty) == "number" and not issecret(qty)) and qty or 1, link, "QUEST_LOOT_RECEIVED", questID)
  end
end

-- What kind of crafting just made an item ("Blacksmithing", "Smelting"...).
-- Smelting is a Mining spell ("Smelt Copper"), so it is told apart by the name
-- of the spell you just cast; otherwise the profession window that is open names it.
local function CraftTypeNow()
  local c = ctx.lastCast
  local recent = c and c.name and (GetTime() - c.time) < 20
  if recent and c.name:find("^Smelt") then return "Smelting" end

  local line
  pcall(function()
    if GetTradeSkillLine then
      line = GetTradeSkillLine()
    elseif C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
      local info = C_TradeSkillUI.GetBaseProfessionInfo()
      line = info and info.professionName
    end
  end)
  if type(line) == "string" and line ~= "" and line ~= "UNKNOWN" and not issecret(line) then
    if line == "Mining" then return "Smelting" end   -- the Mining window only crafts by smelting
    return line
  end
  return "Other crafting"
end

-- An item message in chat. Items that arrive WITHOUT a loot window are sorted
-- by what you were doing:
--   within 3 seconds of a quest turn-in       -> Quest rewards
--   "You create: ..."                         -> Crafting
--   mailbox open                              -> Mail
--   vendor window open                        -> Vendor
--   trade window open                         -> Trades
--   anything else                             -> Other received
-- (The Received Items page shows all but the first.)
local function OnChatLoot(text)
  local itemID, qty, link, kind = ParseReceived(text)
  if not itemID then return end

  -- Quest rewards also reported by QUEST_LOOT_RECEIVED: the 5 second guard
  -- inside LogQuestReward stops them being counted twice.
  if kind == "received" and (ctx.questOpen or GetTime() - ctx.questTime <= 3) then
    LogQuestReward(itemID, qty, link, "chat")
    return
  end

  local category
  if kind == "created" then category = "Crafting"
  elseif ctx.mail then category = "Mail"
  elseif ctx.vendor then category = "Vendor"
  elseif ctx.trade then category = "Trades"
  else category = "Other received" end

  LogEvent(category, itemID, qty, link, GetRealZoneText() or "Unknown")
  if category == "Crafting" then   -- and what kind of crafting made it
    local db = ns.DB()
    db.crafting = db.crafting or {}
    local craftType = CraftTypeNow()
    local ct = db.crafting[craftType]
    if not ct then ct = {}; db.crafting[craftType] = ct end
    ct[itemID] = (ct[itemID] or 0) + (qty or 1)
  end
  if category == "Vendor" then   -- remember which vendor sold it to you
    local v = VendorRecord(GetRealZoneText() or "Unknown", ctx.vendorName or "Unknown vendor")
    v.bought[itemID] = (v.bought[itemID] or 0) + (qty or 1)
  end
  kdebug("received:", link or itemID, "x" .. tostring(qty), "->", category)
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end

-- You started casting something. Remember it if it is a gathering profession.
local function OnSpellSent(unit, target, castGUID, spellID)
  if unit ~= "player" then return end
  if type(spellID) ~= "number" or issecret(spellID) then return end
  local kind = GatherKind(spellID)
  -- target = what the spell was cast on, for example "Copper Vein" or "Peacebloom"
  local targetName
  if type(target) == "string" and not issecret(target) and target ~= "" then targetName = target end
  ctx.lastCast = { name = SpellNameOf(spellID), target = targetName, time = GetTime() }   -- (crafting type, object names)
  kdebug("cast:", spellID, SpellNameOf(spellID) or "?", "on", tostring(targetName), kind and ("-> " .. kind) or "")
  if kind then ctx.gather = { kind = kind, time = GetTime(), used = false, target = targetName } end
end


-- =====================================================================
-- GOLD RECEIVED FROM VENDORS, MAIL, AND TRADES
-- =====================================================================
-- Selling to a vendor, taking gold from the mail, and trades give you money
-- without a loot window or a chat line, so we watch the money you carry:
-- PLAYER_MONEY fires on every change, and a RISE while a vendor window, the
-- mailbox, or a trade is open is gold received. (Money from loot and quests
-- is counted elsewhere and is not counted again here.)

-- Adds gold received (copper) under a category: "Vendor", "Mail" or "Trades".
-- db.moneyIn[category] = { total, times, zones = { [zone] = copper } }
local function AddMoneyIn(category, zone, copper)
  local db = ns.DB()
  db.moneyIn = db.moneyIn or {}
  local c = db.moneyIn[category]
  if not c then c = { total = 0, times = 0, zones = {} }; db.moneyIn[category] = c end
  c.total = c.total + copper
  c.times = c.times + 1
  c.zones[zone] = (c.zones[zone] or 0) + copper
end

-- Your money changed.
local function OnPlayerMoney()
  local ok, now = pcall(GetMoney)
  if not ok or type(now) ~= "number" or issecret(now) then return end
  local before = ctx.lastMoney
  ctx.lastMoney = now
  if not before or now <= before then return end   -- first reading, or money was spent
  local gained = now - before

  local category
  if ctx.vendor then category = "Vendor"
  elseif ctx.mail then category = "Mail"
  -- a trade's gold arrives about when the window closes, so allow 2 seconds after
  elseif ctx.trade or (GetTime() - ctx.tradeClosed) < 2 then category = "Trades" end
  if not category then return end

  local zone = GetRealZoneText() or "Unknown"
  AddMoneyIn(category, zone, gained)
  if category == "Vendor" then
    ctx.visitGold = ctx.visitGold + gained
    local v = VendorRecord(zone, ctx.vendorName or "Unknown vendor")   -- gold from selling to THIS vendor
    v.sold = v.sold + gained
    v.soldTimes = v.soldTimes + 1
  end
  kdebug("gold received:", ns.FormatMoney(gained), "->", category)
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end


-- =====================================================================
-- WHAT YOU DO WITH YOUR LOOT: SELLING, AUCTIONS, TRADES
-- =====================================================================
-- db.sales[itemID] = { vendorCount, vendorGold, aucCount, aucGold } counts what
-- you sold of each item and what it brought in (copper). The Mob Drops page
-- shows it under "Gold made from items".
--   Vendors   a right-click sale in your bags while a vendor window is open
--             (the price is the item's vendor sell price times the stack)
--   Auctions  taking the proceeds from an "Auction successful" mail; the mail
--             names the item and holds the gold
--   Trades    db.trades keeps a log: what you gave and got in each trade
-- None of this changes the gold totals above (those come from your money).

local function SaleRecord(itemID)
  local db = ns.DB()
  db.sales = db.sales or {}
  local s = db.sales[itemID]
  if not s then s = { vendorCount = 0, vendorGold = 0, aucCount = 0, aucGold = 0 }; db.sales[itemID] = s end
  return s
end

-- You right-clicked an item in a bag. With a vendor window open that sells it.
local lastSaleKey, lastSaleTime = nil, 0
local function OnUseContainerItem(bag, slot)
  if not ctx.vendor then return end
  pcall(function()
    local link, count
    if C_Container and C_Container.GetContainerItemInfo then
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info then link, count = info.hyperlink, info.stackCount end
    elseif GetContainerItemInfo then
      local _, c, _, _, _, _, l = GetContainerItemInfo(bag, slot)
      link, count = l, c
    end
    if type(link) ~= "string" then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    -- The old and the new bag function can both report one click: count it once
    local key, now = tostring(bag) .. ":" .. tostring(slot), GetTime()
    if key == lastSaleKey and now - lastSaleTime < 0.3 then return end
    lastSaleKey, lastSaleTime = key, now

    -- The vendor's price for ONE item is the 11th value of GetItemInfo
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local price = select(11, getInfo(link))
    if type(price) ~= "number" or price <= 0 then return end   -- no value: the vendor will not buy it
    count = count or 1

    local sr = SaleRecord(itemID)
    sr.vendorCount = sr.vendorCount + count
    sr.vendorGold = sr.vendorGold + price * count
    -- also under the vendor you sold it to
    local v = VendorRecord(GetRealZoneText() or "Unknown", ctx.vendorName or "Unknown vendor")
    v.soldItems = v.soldItems or {}
    local si = v.soldItems[itemID]
    if not si then si = { n = 0, gold = 0 }; v.soldItems[itemID] = si end
    si.n = si.n + count
    si.gold = si.gold + price * count
    kdebug("sold to vendor:", link, "x" .. count, ns.FormatMoney(price * count))
    local db = ns.DB(); db.items = db.items or {}; db.items[itemID] = db.items[itemID] or link
  end)
end

-- You took the gold (or everything) from a mail. If it is an auction sale, the
-- mail's invoice names the item, so the gold is credited to that item.
local lastMailKey, lastMailTime = nil, 0
local function OnTakeMail(index)
  if not ctx.mail or type(index) ~= "number" then return end
  pcall(function()
    local header = GetInboxHeaderInfo or (C_Mail and C_Mail.GetInboxHeaderInfo)
    if not header then return end
    local _, _, _, subject, money = header(index)
    if type(subject) ~= "string" or type(money) ~= "number" or money <= 0 then return end

    -- Only auction sales: the subject reads "Auction successful: <item>"
    local pattern = AUCTION_SOLD_MAIL_SUBJECT and FormatToPattern(AUCTION_SOLD_MAIL_SUBJECT)
    local nameFromSubject = pattern and subject:match(pattern)
    if not nameFromSubject then return end

    local key, now = index .. ":" .. subject .. ":" .. money, GetTime()
    if key == lastMailKey and now - lastMailTime < 1 then return end
    lastMailKey, lastMailTime = key, now

    -- The invoice gives the exact item name and how many were sold
    local invoice = GetInboxInvoiceInfo or (C_Mail and C_Mail.GetInboxInvoiceInfo)
    local itemName, itemCount = nameFromSubject, 1
    if invoice then
      -- GetInboxInvoiceInfo returns: invoiceType, itemName, playerName, bid, buyout,
      -- deposit, consignment, moneyDelay, etaHour, etaMin, count (the 11th value)
      local r = { invoice(index) }
      local invoiceType, name, count = r[1], r[2], r[11]
      if invoiceType == "seller" and type(name) == "string" and name ~= "" then
        itemName = name
        itemCount = (type(count) == "number" and count > 0) and count or 1
      end
    end

    -- Find the item ID from the links we have saved
    local db = ns.DB()
    local itemID
    for id, link in pairs(db.items or {}) do
      if link:match("%[(.-)%]") == itemName then itemID = id; break end
    end
    if not itemID then kdebug("auction sale of an item we have no ID for:", itemName); return end

    local sr = SaleRecord(itemID)
    sr.aucCount = sr.aucCount + itemCount
    sr.aucGold = sr.aucGold + money
    kdebug("auction sale:", itemName, "x" .. itemCount, ns.FormatMoney(money))
    if ns.RefreshIfOpen then ns.RefreshIfOpen() end
  end)
end

-- Hook the bag and mail functions (both the old global names and the newer
-- C_Container / C_Mail ones; whichever exist). Hooks run AFTER the game's own
-- function, and cannot change what it does.
pcall(function()
  if UseContainerItem then hooksecurefunc("UseContainerItem", OnUseContainerItem) end
  if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", OnUseContainerItem) end
  if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", OnTakeMail) end
  if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", OnTakeMail) end
  if C_Mail then
    if C_Mail.TakeInboxMoney then hooksecurefunc(C_Mail, "TakeInboxMoney", OnTakeMail) end
    if C_Mail.AutoLootMailItem then hooksecurefunc(C_Mail, "AutoLootMailItem", OnTakeMail) end
  end
end)

-- Both sides pressed Accept: remember what is in the trade window now. It is
-- written to the trade log when the window closes.
local function OnTradeAccept(playerAccepted, targetAccepted)
  if not (playerAccepted == 1 and targetAccepted == 1) then return end
  local snap = { at = GetTime(), gave = {}, got = {}, gaveGold = 0, gotGold = 0, partner = ctx.tradePartner or "Unknown" }
  pcall(function()
    local db = ns.DB()
    db.items = db.items or {}
    for i = 1, 6 do
      local link = GetTradePlayerItemLink(i)
      if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then
          local _, _, n = GetTradePlayerItemInfo(i)
          snap.gave[id] = (snap.gave[id] or 0) + (n or 1)
          db.items[id] = db.items[id] or link
        end
      end
      local tlink = GetTradeTargetItemLink(i)
      if tlink then
        local id = tonumber(tlink:match("item:(%d+)"))
        if id then
          local _, _, n = GetTradeTargetItemInfo(i)
          snap.got[id] = (snap.got[id] or 0) + (n or 1)
          db.items[id] = db.items[id] or tlink
        end
      end
    end
    snap.gaveGold = GetPlayerTradeMoney() or 0
    snap.gotGold = GetTargetTradeMoney() or 0
  end)
  ctx.tradeSnap = snap
end

-- The trade window closed. If both had accepted just before, log the trade:
-- db.trades (newest first, the last 200) = { t, partner, zone, gave, got, gaveGold, gotGold }.
local function LogTrade()
  local snap = ctx.tradeSnap
  ctx.tradeSnap = nil
  if not snap or GetTime() - snap.at > 10 then return end
  if next(snap.gave) == nil and next(snap.got) == nil and snap.gaveGold == 0 and snap.gotGold == 0 then return end
  local db = ns.DB()
  db.trades = db.trades or {}
  table.insert(db.trades, 1, { t = time(), partner = snap.partner, zone = GetRealZoneText() or "Unknown",
                               gave = snap.gave, got = snap.got, gaveGold = snap.gaveGold, gotGold = snap.gotGold })
  while #db.trades > 200 do table.remove(db.trades) end
  kdebug("trade logged with", snap.partner)
  if ns.RefreshIfOpen then ns.RefreshIfOpen() end
end


-- =====================================================================
-- COIN (GOLD) CAPTURE
-- =====================================================================
-- A loot slot of type "money" has quantity 0; the amount is only in its text,
-- for example "5 copper" (tested on this client). So we read the text.
-- The game's own words for gold / silver / copper (GOLD_AMOUNT and friends,
-- like "%d Gold") are used, so this also works in other languages.

local MONEY_SLOT = ns.MONEY_SLOT

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
      local category = CategoryFor(guid, kind, fishing)   -- Mobs / Fishing / Mining / ...
      local coin = share[i]

      AddGold(category, zone, coin)   -- overall totals, by source and zone

      -- Per creature: total coin and how many corpses dropped coin
      -- (not for skinning, which is a separate loot from the same corpse)
      if kind == "Creature" and category == "Mobs" then
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
pcall(f.RegisterEvent, f, "PLAYER_LOGOUT")  -- you are logging out or reloading: keep this session as the "previous" one
-- Quest rewards and gathering (see WHERE LOOT CAME FROM above)
pcall(f.RegisterEvent, f, "QUEST_COMPLETE")            -- the quest reward window opened
pcall(f.RegisterEvent, f, "QUEST_TURNED_IN")           -- you turned in a quest
pcall(f.RegisterEvent, f, "QUEST_LOOT_RECEIVED")       -- a quest reward item arrived
pcall(f.RegisterEvent, f, "CHAT_MSG_LOOT")             -- "You receive item: ..." lines
-- Windows that tell us where an item came from (vendor, mail, trade). Any the
-- client refuses are listed by /lootlog kills.
ns.failedEvents = {}
for _, ev in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
                      "TRADE_SHOW", "TRADE_CLOSED", "PLAYER_MONEY", "TRADE_ACCEPT_UPDATE", "QUEST_FINISHED" }) do
  if not pcall(f.RegisterEvent, f, ev) then ns.failedEvents[#ns.failedEvents + 1] = ev end
end
pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SENT", "player")          -- you began a cast
pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_INTERRUPTED", "player")   -- ...cancelled
pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_FAILED", "player")        -- ...failed
-- Both loot events can fire for the same corpse. The "seen" and "counted"
-- tables make sure it is only logged once.

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
  -- Name-cache events (and the target check) do their job and stop.
  if event == "PLAYER_TARGET_CHANGED" then
    CacheName("target")
    CheckTarget()   -- also marks it as yours if you are fighting it
    return
  end
  if event == "UPDATE_MOUSEOVER_UNIT" then return CacheName("mouseover") end

  -- Quest and gathering events: stop after handling.
  if event == "QUEST_COMPLETE" then return OnQuestComplete() end
  if event == "QUEST_TURNED_IN" then return OnQuestTurnedIn(arg1, arg2, arg3) end
  if event == "QUEST_LOOT_RECEIVED" then return OnQuestLoot(arg1, arg2, arg3) end
  if event == "CHAT_MSG_LOOT" then return OnChatLoot(arg1) end
  if event == "PLAYER_MONEY" then return OnPlayerMoney() end
  if event == "MERCHANT_SHOW" then
    ctx.vendor = true
    ctx.visitGold = 0
    -- Who you are talking to ("npc" is the unit you are interacting with)
    local ok, n = pcall(UnitName, "npc")
    ctx.vendorName = (ok and type(n) == "string" and n ~= "" and not issecret(n)) and n or "Unknown vendor"
    return
  end
  if event == "MERCHANT_CLOSED" then
    ctx.vendor = false
    if ctx.visitGold > 0 and ns.AnnounceSale then ns.AnnounceSale(ctx.visitGold, ctx.vendorName) end   -- a line about the sale (Messages.lua)
    ctx.visitGold = 0
    return
  end
  if event == "MAIL_SHOW" then ctx.mail = true; return end
  if event == "MAIL_CLOSED" then ctx.mail = false; return end
  if event == "TRADE_SHOW" then
    ctx.trade = true
    local ok, n = pcall(UnitName, "NPC")   -- in a trade, the other player is the "NPC" unit
    ctx.tradePartner = (ok and type(n) == "string" and n ~= "" and not issecret(n)) and n or "Unknown"
    return
  end
  if event == "TRADE_ACCEPT_UPDATE" then return OnTradeAccept(arg1, arg2) end
  if event == "QUEST_FINISHED" then ctx.questOpen = false; ctx.questTime = GetTime(); return end
  if event == "TRADE_CLOSED" then ctx.trade = false; ctx.tradeClosed = GetTime(); LogTrade(); return end
  if event == "UNIT_SPELLCAST_SENT" then return OnSpellSent(arg1, arg2, arg3, arg4) end
  if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    if ctx.gather and not ctx.gather.used then ctx.gather = nil end   -- the gather did not happen
    return
  end

  -- Kill detection events: stop after handling.
  if event == "UNIT_DIED" then return KillFor(arg1, "UNIT_DIED") end
  if event == "UNIT_HEALTH" or event == "PLAYER_REGEN_DISABLED" then return CheckTarget() end
  if event == "PLAYER_LOGOUT" then return ns.SaveSession() end
  if event == "PLAYER_REGEN_ENABLED" then
    CheckTarget()
    PruneEngaged()
    return
  end

  -- Zone events: remember the place, redraw if the window is open, and stop.
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
     or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    if event == "PLAYER_ENTERING_WORLD" then pcall(function() ctx.lastMoney = GetMoney() end) end   -- starting point for money changes
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
      local icon, name, qty, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
      -- Pull the item ID out of the link text ("...|Hitem:12345:...|h...")
      local itemID = link and tonumber(link:match("item:(%d+)"))
      if itemID then
        -- Save the link and icon so the UI can show names and icons later
        db.items = db.items or {}
        db.items[itemID] = link
        db.icons = db.icons or {}
        db.icons[itemID] = icon
        -- The loot window says when an item belongs to a quest; remember it
        -- (shared by all characters) so the drop lists can set quest items apart
        if isQuestItem then
          db.questItems = db.questItems or {}
          db.questItems[itemID] = true
        end

        -- One item slot can come from several corpses (area loot), so loop
        -- over every source. src = { guid1, qty1, guid2, qty2, ... }
        local src = { GetLootSourceInfo(slot) }
        for i = 1, #src, 2 do
          local guid = src[i]
          local kind, _, _, _, _, id = strsplit("-", guid)

          -- Decide which log category this loot belongs to.
          -- Add new categories (quest, mail...) by extending this check.
          local category = CategoryFor(guid, kind, fishing)   -- Mobs / Fishing / Mining / ...
          -- Gathering and chests are also logged per node (which vein, herb, or chest)
          local node = NoteNode(guid, kind, id, category, zone)

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
            if node then node.items[itemID] = (node.items[itemID] or 0) + amount end   -- items per node
            -- A chat message if this catch earned a star (Messages.lua)
            if category == "Fishing" and ns.AnnounceFish then ns.AnnounceFish(itemID, amount) end
            -- Session totals (the Session page)
            local sess = ns.session
            local q = quality or 1
            sess.items = sess.items + amount
            sess.itemQty[itemID] = (sess.itemQty[itemID] or 0) + amount
            sess.byQuality[q] = (sess.byQuality[q] or 0) + amount
            -- A chat message for blue and better drops (Messages.lua)
            if q >= 3 and ns.AnnounceDrop then
              ns.AnnounceDrop(link, q, SourceText(category, id, guid))
            end
          end

          -- Per-mob stats: only for creatures we killed (not skinning, which is
          -- a separate loot from the same corpse). Used by the Mob Drops page.
          if kind == "Creature" and category == "Mobs" then
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
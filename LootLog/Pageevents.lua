--[[
=====================================================================
 PageEvents.lua - plain text pages (Fishing, Gathering, Quest, Gold)
=====================================================================
 Each page here is a function that takes the database and returns one
 block of text. UI.lua shows that text in the scrolling text area.

 TO ADD A TEXT PAGE:
   1. Add an entry to PAGES in UI.lua  ({ key = "mail", label = "Mail" })
   2. Add a matching entry to ns.BUILDERS at the bottom of this file
=====================================================================
]]

local ADDON, ns = ...

-- Builds a text list for an event category, grouped by zone.
-- Returns emptyMsg when there is no data yet.
local function EventPage(db, category, emptyMsg)
  local zones = db.events[category]
  if not zones or not next(zones) then return emptyMsg end

  -- Sort zone names so the page order is stable
  local zoneNames = {}
  for z in pairs(zones) do zoneNames[#zoneNames + 1] = z end
  table.sort(zoneNames)

  local lines = {}
  for _, zone in ipairs(zoneNames) do
    -- Total items in this zone, used for the "% of zone" figure
    local total = 0
    for _, e in pairs(zones[zone]) do total = total + e.count end
    -- |cffffd100 ... |r is WoW color markup (gold text)
    lines[#lines + 1] = string.format("|cffffd100%s|r - %d items", zone, total)
    -- Most numerous first, then by name, so the order is stable
    local list = {}
    for itemID, e in pairs(zones[zone]) do list[#list + 1] = { id = itemID, e = e } end
    table.sort(list, function(a, b)
      if a.e.count ~= b.e.count then return a.e.count > b.e.count end
      local na, nb = a.e.name or "", b.e.name or ""
      if na ~= nb then return na < nb end
      return a.id < b.id
    end)
    for _, it in ipairs(list) do
      -- A small picture of the item in front of its name (|T<icon>:14|t draws it inline)
      local icon = ns.GetIcon(db, it.id)
      local pic = icon and ("|T" .. icon .. ":14|t ") or ""
      lines[#lines + 1] = string.format("    %s%s [ID %d] x%d   (%.1f%% of zone)",
        pic, ns.ItemText(db, it.id, it.e.name), it.id, it.e.count, 100 * it.e.count / math.max(total, 1))
    end
    lines[#lines + 1] = " "   -- blank spacer line
  end
  return table.concat(lines, "\n")
end

-- Gold page: total coin looted, then coin by source and zone, then the
-- creatures that pay best per kill. All amounts are stored in copper.
--   db.gold = { total, drops, events = { [category] = { [zone] = copper } } }
--   db.mobs[npcID].gold / .goldDrops  (set in Capture.lua)
local function GoldPage(db)
  local g = db.gold
  if not (g and g.total and g.total > 0) then
    return "No coin recorded yet. Loot some creatures and it will appear here."
  end

  local lines = {}
  lines[#lines + 1] = string.format("|cffffd100Total coin looted|r  %s   (%d coin drops)",
    ns.FormatMoney(g.total), g.drops or 0)
  lines[#lines + 1] = " "

  -- By source (Mobs, Fishing, Objects...) and zone
  local cats = {}
  for c in pairs(g.events or {}) do cats[#cats + 1] = c end
  table.sort(cats)
  for _, category in ipairs(cats) do
    local zones = g.events[category]
    local catTotal = 0
    for _, v in pairs(zones) do catTotal = catTotal + v end
    lines[#lines + 1] = string.format("|cff00ff00%s|r   %s", category, ns.FormatMoney(catTotal))
    local zl = {}
    for z in pairs(zones) do zl[#zl + 1] = z end
    table.sort(zl)
    for _, z in ipairs(zl) do
      lines[#lines + 1] = string.format("    %s   %s", z, ns.FormatMoney(zones[z]))
    end
    lines[#lines + 1] = " "
  end

  -- Creatures that pay best: average coin per kill, top 15
  local list = {}
  for npcID, m in pairs(db.mobs) do
    if m.gold and m.gold > 0 and m.kills > 0 then
      list[#list + 1] = {
        id = npcID, name = m.name or ("ID " .. npcID),
        total = m.gold, kills = m.kills, drops = m.goldDrops or 0,
      }
    end
  end
  table.sort(list, function(a, b)
    local x, y = a.total / a.kills, b.total / b.kills
    if x ~= y then return x > y end
    return a.id < b.id
  end)
  if #list > 0 then
    lines[#lines + 1] = "|cffffd100Best creatures (coin per kill)|r"
    for i = 1, math.min(#list, 15) do
      local e = list[i]
      lines[#lines + 1] = string.format("    %s [ID %d]   %s per kill   (%d kills, coin on %d)",
        e.name, e.id, ns.FormatMoney(math.floor(e.total / e.kills)), e.kills, e.drops)
    end
  end
  return table.concat(lines, "\n")
end

-- Quest Rewards page, second tab: every quest you have turned in, newest
-- first, with the date, the level you were, and the XP. Quests with no
-- reward are included. Recorded in Capture.lua as db.quests[questID] =
-- { name, t (time), level, xp, money, zone, count, rewards = { [itemID] = qty } }.
local function QuestsDonePage(db)
  local list = {}
  for questID, q in pairs(db.quests or {}) do
    if q.t then list[#list + 1] = { id = questID, q = q } end   -- skip half-made records with no turn-in
  end
  if #list == 0 then
    return "No completed quests recorded yet. Turn in a quest and it will appear here."
  end
  table.sort(list, function(a, b)
    if a.q.t ~= b.q.t then return a.q.t > b.q.t end
    return a.id < b.id
  end)

  local lines = { string.format("|cffffd100%d quests completed|r", #list), " " }
  for _, e in ipairs(list) do
    local q = e.q
    lines[#lines + 1] = string.format("|cffffd100%s|r  (quest %d)%s",
      q.name or "Unknown quest", e.id, (q.count and q.count > 1) and string.format("  - turned in %d times", q.count) or "")
    -- Date, level, XP, coin, zone on one line
    local parts = { date("%Y-%m-%d %H:%M", q.t) }
    if q.level then parts[#parts + 1] = "level " .. q.level end
    parts[#parts + 1] = q.xp and (q.xp .. " XP") or "XP not reported"
    if q.money and q.money > 0 then parts[#parts + 1] = ns.FormatMoney(q.money) end
    if q.zone then parts[#parts + 1] = q.zone end
    lines[#lines + 1] = "    " .. table.concat(parts, "  |  ")
    -- Reward items, if any
    local rewards = {}
    for itemID, qty in pairs(q.rewards or {}) do
      rewards[#rewards + 1] = ns.ItemText(db, itemID) .. ((qty > 1) and (" x" .. qty) or "")
    end
    if #rewards > 0 then
      table.sort(rewards)
      lines[#lines + 1] = "    Rewards: " .. table.concat(rewards, ", ")
    end
    lines[#lines + 1] = " "
  end
  return table.concat(lines, "\n")
end

-- Tabs shown above a text page. ns.GetSubTab(page) (Core.lua) says which
-- one is selected, and the builder below picks the matching text.
ns.SUBTABS = {
  received = {   -- Received Items page: where an item came from
    { key = "Vendor",         label = "Vendor" },
    { key = "Mail",           label = "Mail" },
    { key = "Crafting",       label = "Crafting" },
    { key = "Trades",         label = "Trades" },
    { key = "Other received", label = "Other" },
  },
  quest = {
    { key = "rewards",   label = "Rewards" },
    { key = "completed", label = "Completed Quests" },
  },
}

-- Gathering page, organized by ZONE, then by kind of gathering (Mining, Herb
-- gathering, Skinning, other objects), then by NODE (Copper Vein, Peacebloom,
-- a boar you skinned, a chest...), with the items each one gave.
--   db.gather[category][zone][nodeKey] = { id, kind, gathers, items = { [itemID] = qty } }
--   db.nodeNames[nodeKey] = name remembered from what you cast on
-- Gathers made before node tracking exist only in db.events, so whatever the
-- node records do not account for is listed as "Earlier gathers".
local GATHER_SECTIONS = {
  { key = "Mining",    label = "Mining",                           verb = "gathered", per = "node" },
  { key = "Herbalism", label = "Herb gathering",                   verb = "gathered", per = "node" },
  { key = "Skinning",  label = "Skinning",                         verb = "skinned",  per = "skin" },
  { key = "Objects",   label = "Other objects (chests and so on)", verb = "opened",   per = "object" },
}

-- Items of a node, most numerous first, as { itemID, qty } pairs.
local function SortedNodeItems(items)
  local list = {}
  for itemID, qty in pairs(items) do list[#list + 1] = { id = itemID, qty = qty } end
  table.sort(list, function(a, b)
    if a.qty ~= b.qty then return a.qty > b.qty end
    return a.id < b.id
  end)
  return list
end

local function GatheringPage(db)
  -- Every zone that has anything in these categories
  local zoneSet = {}
  for _, sec in ipairs(GATHER_SECTIONS) do
    for zone in pairs((db.gather and db.gather[sec.key]) or {}) do zoneSet[zone] = true end
    for zone in pairs(db.events[sec.key] or {}) do zoneSet[zone] = true end
  end
  local zones = {}
  for z in pairs(zoneSet) do zones[#zones + 1] = z end
  if #zones == 0 then return "No gathering recorded yet." end
  table.sort(zones)

  local lines = {}
  for _, zone in ipairs(zones) do
    lines[#lines + 1] = "|cffffd100" .. zone .. "|r"

    for _, sec in ipairs(GATHER_SECTIONS) do
      local nodes = (db.gather and db.gather[sec.key] and db.gather[sec.key][zone]) or {}
      local logged = (db.events[sec.key] and db.events[sec.key][zone]) or {}

      -- The nodes, sorted by name, and what they add up to (to find the leftover)
      local list, accounted = {}, {}
      for key, n in pairs(nodes) do
        local name = (db.nodeNames and db.nodeNames[key])
          or ((n.kind == "Creature") and ("Creature " .. n.id) or ("Object " .. n.id))
        list[#list + 1] = { key = key, n = n, name = name }
        for itemID, qty in pairs(n.items) do accounted[itemID] = (accounted[itemID] or 0) + qty end
      end
      table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
      end)

      -- Items logged for this zone that no node record covers (older gathers)
      local leftover = {}
      for itemID, e in pairs(logged) do
        local rest = e.count - (accounted[itemID] or 0)
        if rest > 0 then leftover[#leftover + 1] = { id = itemID, qty = rest, name = e.name } end
      end
      table.sort(leftover, function(a, b)
        if a.qty ~= b.qty then return a.qty > b.qty end
        return a.id < b.id
      end)

      if #list > 0 or #leftover > 0 then
        lines[#lines + 1] = "  |cff00ff00" .. sec.label .. "|r"
        for _, e in ipairs(list) do
          local n = e.n
          local items = SortedNodeItems(n.items)
          -- Picture next to the node: the icon of the item it gives most
          -- (a Copper Vein shows Copper Ore). |T<icon>:16|t draws an inline picture.
          local icon = items[1] and ns.GetIcon(db, items[1].id)
          lines[#lines + 1] = string.format("    %s%s   (%s %d %s)",
            icon and ("|T" .. icon .. ":16|t ") or "", e.name,
            sec.verb, n.gathers, n.gathers == 1 and "time" or "times")
          for _, it in ipairs(items) do
            lines[#lines + 1] = string.format("        %s x%d   (%.1f per %s)",
              ns.ItemText(db, it.id), it.qty, it.qty / math.max(n.gathers, 1), sec.per)
          end
        end
        if #leftover > 0 then
          lines[#lines + 1] = "    Earlier gathers (node not recorded)"
          for _, it in ipairs(leftover) do
            lines[#lines + 1] = string.format("        %s x%d", ns.ItemText(db, it.id, it.name), it.qty)
          end
        end
      end
    end
    lines[#lines + 1] = " "
  end
  return table.concat(lines, "\n")
end

-- Session page: this session (since you logged in or reloaded) and the
-- previous one. Both are "snapshots" (see ns.SessionSnapshot in Core.lua).
-- The current one is not saved; it becomes the previous one when you log out
-- or reload (ns.SaveSession), unless nothing happened in it. The page is
-- redrawn when you open it or loot something.
local QUALITY_NAMES  = { [0] = "Grey", [1] = "White", [2] = "Green", [3] = "Blue", [4] = "Epic", [5] = "Legendary" }
local QUALITY_COLORS = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

-- Appends the lines describing one session (time, kills, coin, items, items
-- by quality, most killed, most looted) to `lines`.
local function AddSessionLines(lines, db, st)
  local secs = st.seconds
  local hours = secs / 3600
  local function perHour(n)   -- needs a minute of play for the number to mean anything
    if secs < 60 then return "--" end
    return string.format("%.0f", n / hours)
  end

  -- 1h 23m 05s
  local h, m, s = math.floor(secs / 3600), math.floor(secs % 3600 / 60), math.floor(secs % 60)
  local duration = (h > 0 and (h .. "h ") or "") .. m .. "m " .. string.format("%02d", s) .. "s"

  lines[#lines + 1] = string.format("Time        %s", duration)
  lines[#lines + 1] = string.format("Kills       %d    (%s per hour)", st.kills, perHour(st.kills))
  lines[#lines + 1] = string.format("Coin        %s    (%s per hour)", ns.FormatMoney(st.coin),
    secs < 60 and "--" or ns.FormatMoney(math.floor(st.coin / hours)))
  lines[#lines + 1] = string.format("Items       %d    (%s per hour)", st.items, perHour(st.items))

  -- Items by quality, in their colours
  local parts = {}
  for q = 0, 5 do
    local n = st.byQuality[q]
    if n and n > 0 then
      parts[#parts + 1] = string.format("|cff%s%s %d|r", QUALITY_COLORS[q], QUALITY_NAMES[q], n)
    end
  end
  if #parts > 0 then lines[#lines + 1] = "            " .. table.concat(parts, "   ") end

  if #st.mobs > 0 then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd100Most killed|r"
    for _, e in ipairs(st.mobs) do
      lines[#lines + 1] = string.format("    %s  x%d", e.name, e.n)
    end
  end

  if #st.loot > 0 then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd100Most looted|r"
    for _, e in ipairs(st.loot) do
      local icon = ns.GetIcon(db, e.id)
      local pic = icon and ("|T" .. icon .. ":14|t ") or ""
      lines[#lines + 1] = string.format("    %s%s  x%d", pic, ns.ItemText(db, e.id), e.n)
    end
  end
end

local function SessionPage(db)
  local lines = { "|cffffd100This session|r   since you logged in or reloaded", " " }

  local now = ns.SessionSnapshot()
  if now.kills == 0 and now.items == 0 and now.coin == 0 then
    lines[#lines + 1] = "Nothing yet this session. Kill or loot something and it shows up here."
  else
    AddSessionLines(lines, db, now)
  end

  -- The previous session of the character you are playing
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cffffd100Previous session|r"
  local prev = ns.DB().lastSession
  if prev then
    lines[#lines + 1] = ns.DateTimeText(prev.startTime) .. " to " .. date("%H:%M", prev.endTime) ..
                        "   (kept when you log out or reload; sessions with nothing in them are skipped)"
    lines[#lines + 1] = " "
    AddSessionLines(lines, db, prev)
  else
    lines[#lines + 1] = "None yet. This session is kept when you log out or reload."
  end
  return table.concat(lines, "\n")
end

-- Help page: what the addon is, how to use each page, and the /commands.
-- KEEP THIS UP TO DATE: when you add or change a /lootlog command in UI.lua,
-- edit the "Commands" part below too.
local function HelpPage()
  local H = "|cffffd100"   -- gold heading
  local C = "|cff00ff00"   -- green command
  local lines = {
    H .. "LootLog|r   version " .. ns.VERSION,
    "Keeps a record of what you kill, loot, gather, catch, buy, and complete in World of Warcraft Forever,",
    "and turns it into logs you can browse. Everything is saved on your account and stays on your computer.",
    " ",
    H .. "The pages|r",
    "  Hunting Log       cards for every creature, greyed out until you kill one. Stars for kills. Click a card",
    "                    for details and its loot. Right-click a card to set its class (Elite, Rare, Boss,",
    "                    Critter, Quest) or mark it 'Not in game version'.",
    "  Mob Drops         for each creature: kills, drops, drop rates, and coin. Click the column headings to sort.",
    "                    Right-click a creature in the list to delete its data.",
    "  Fishing Log       everything that can be fished up, greyed out until caught. Stars for catches.",
    "  Quest Rewards     reward items, and a Completed Quests tab (date, level, XP).",
    "  Gold              coin looted, by source and zone, and the creatures that pay best.",
    "  Gathering         mining, herbs, and skinning by zone and node.",
    "  Received Items    items from vendors, mail, crafting, and trades.",
    "  Session           kills, coin, and items since you logged in, with per-hour numbers, and the session before.",
    " ",
    H .. "Tips|r",
    "  Each character has its own logs. Tick 'All characters' (bottom left of the window) to see them combined.",
    "  Class choices and 'Not in game version' flags are shared by all characters, since a creature is the same for everyone.",
    "  Drag the window with the left mouse button. Drag the LootLog button with the right mouse button.",
    "  Hover over a card, tile, or item for details. Esc closes the window.",
    "  Chat messages announce new stars, rare and epic drops, and zones you have fully cleared. Use the check boxes at",
    "  the top of this page: 'Reduce messages' keeps only stars, rare drops, and zone clears; 'Stop messages' turns them all off.",
    "  Hover a hostile or neutral creature anywhere to see how often you have killed it.",
    " ",
    H .. "Commands|r",
    "  " .. C .. "/lootlog|r                       open or close the window",
    "  " .. C .. "/lootlog reset|r                 asks first, then clears THIS character's data (kills, loot, coin, quests,",
    "                                  creatures met). Other characters, your settings, class choices, and flags are kept",
    "  " .. C .. "/lootlog all|r                    same as the 'All characters' check box",
    "  " .. C .. "/lootlog characters|r             list every character with data, with kills and last played",
    "  " .. C .. "/lootlog messages|r              step through all, reduced, and off (or type /lootlog messages all|reduced|off)",
    "  " .. C .. "/lootlog button|r                 show or hide the on-screen LootLog button (/lootlog still opens the window)",
    "  " .. C .. "/lootlog tooltip|r                turn the 'killed N times' line on creature tooltips on or off",
    "  " .. C .. "/lootlog faction A|H|all|mine|r  choose whose Hunting Log you see: Alliance, Horde, both,",
    "                                  or your own character's faction (the default)",
    "  " .. C .. "/lootlog kills|r                 turn on messages that show how kills, coin, quests, gathering,",
    "                                  and received items are being detected (for troubleshooting)",
    "  " .. C .. "/lootlog debug|r                 print what the Hunting Log loaded and how many creatures it lists",
  }
  return table.concat(lines, "\n")
end

-- Page key -> function that returns that page's text.
-- "mobs" is not here because it has its own two-pane layout (PageMobs.lua).
ns.BUILDERS = {
  help      = function() return HelpPage() end,
  session   = SessionPage,
  quest     = function(db)
    if ns.GetSubTab("quest") == "completed" then return QuestsDonePage(db) end
    return EventPage(db, "Quest", "No quest rewards recorded yet. Turn in a quest that gives an item.")
  end,
  gold      = GoldPage,
  gathering = GatheringPage,
  received  = function(db)
    -- The tab keys are the event categories Capture.lua logs under
    local tab = ns.GetSubTab("received")
    local empty = {
      ["Vendor"]         = "Nothing bought from vendors yet.",
      ["Mail"]           = "Nothing taken from your mailbox yet.",
      ["Crafting"]       = "Nothing crafted yet.",
      ["Trades"]         = "Nothing received in trades yet.",
      ["Other received"] = "Nothing else yet. Items that arrive without a loot window, a vendor, mail, a trade, or a craft are listed here.",
    }
    return EventPage(db, tab, empty[tab])
  end,
}
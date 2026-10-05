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
local function EventPage(db, category, emptyMsg, opts)
  opts = opts or {}
  local events = db.events[category] or {}
  local money = opts.money                              -- gold received: { total, times, zones = { [zone] = copper } }
  local moneyZones = (money and money.zones) or {}
  local moneyLabel = opts.moneyLabel or "Gold received"
  local coin = "|T" .. ns.COIN_ICON .. ":14|t "         -- the gold coin picture

  -- Zones that have items, gold, or both; sorted so the page order is stable
  local zoneSet = {}
  for z in pairs(events) do zoneSet[z] = true end
  for z in pairs(moneyZones) do zoneSet[z] = true end
  local zoneNames = {}
  for z in pairs(zoneSet) do zoneNames[#zoneNames + 1] = z end
  if #zoneNames == 0 then return emptyMsg end
  table.sort(zoneNames)

  local lines = {}
  -- Gold received in total, at the top
  if money and (money.total or 0) > 0 then
    lines[#lines + 1] = string.format("%s|cffffd100%s|r   %s   (%d times)",
      coin, moneyLabel, ns.FormatMoney(money.total), money.times or 0)
    lines[#lines + 1] = " "
  end

  for _, zone in ipairs(zoneNames) do
    local items = events[zone] or {}
    -- Total items in this zone, used for the "% of zone" figure
    local total = 0
    for _, e in pairs(items) do total = total + e.count end
    -- |cffffd100 ... |r is WoW color markup (gold text)
    if next(items) ~= nil then
      lines[#lines + 1] = string.format("|cffffd100%s|r - %d items", zone, total)
    else
      lines[#lines + 1] = string.format("|cffffd100%s|r", zone)   -- only gold here, no items
    end
    -- Gold received in this zone
    if moneyZones[zone] then
      lines[#lines + 1] = string.format("    %s%s   %s", coin, moneyLabel, ns.FormatMoney(moneyZones[zone]))
    end
    -- Most numerous first, then by name, so the order is stable
    local list = {}
    for itemID, e in pairs(items) do list[#list + 1] = { id = itemID, e = e } end
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
      -- "% of zone" is left out when opts.percent is false (Quest Rewards)
      local share = ""
      if opts.percent ~= false then
        share = string.format("   (%.1f%% of zone)", 100 * it.e.count / math.max(total, 1))
      end
      lines[#lines + 1] = string.format("    %s%s [ID %d] x%d%s",
        pic, ns.ItemText(db, it.id, it.e.name), it.id, it.e.count, share)
    end
    lines[#lines + 1] = " "   -- blank spacer line
  end
  return table.concat(lines, "\n")
end

-- Gold page: total coin looted, then coin by source and zone, then the
-- creatures that pay best per kill. All amounts are stored in copper.
--   db.gold = { total, drops, events = { [category] = { [zone] = copper } } }
--   db.mobs[npcID].gold / .goldDrops  (set in Capture.lua)
-- Gold page, "All gold" tab: every kind of gold you have received, added up.
--   Looted coin (db.gold.events: creatures, chests, fishing, gathering, quests...)
--   Gold from selling to vendors, taking from mail, and trades (db.moneyIn)
local LOOT_LABELS = {
  Mobs = "Looted from creatures", Objects = "Looted from chests and objects", Fishing = "Fished up",
  Mining = "Mining", Herbalism = "Herb gathering", Skinning = "Skinning", Quest = "Quest rewards",
  Other = "Other loot",
}
local MONEY_LABELS = {
  Vendor = "Selling to vendors", Mail = "Taken from mail", Trades = "Received in trades",
}

local function GoldAllPage(db)
  local sources, zoneTotals, total = {}, {}, 0

  for cat, zones in pairs((db.gold and db.gold.events) or {}) do
    local sum = 0
    for zone, n in pairs(zones) do
      sum = sum + n
      zoneTotals[zone] = (zoneTotals[zone] or 0) + n
    end
    if sum > 0 then sources[#sources + 1] = { label = LOOT_LABELS[cat] or cat, copper = sum } end
    total = total + sum
  end
  for cat, m in pairs(db.moneyIn or {}) do
    local sum = m.total or 0
    for zone, n in pairs(m.zones or {}) do zoneTotals[zone] = (zoneTotals[zone] or 0) + n end
    if sum > 0 then sources[#sources + 1] = { label = MONEY_LABELS[cat] or cat, copper = sum } end
    total = total + sum
  end
  if total == 0 then
    return "No gold recorded yet. Loot some coin, sell to a vendor, or take gold from the mail and it will appear here."
  end
  table.sort(sources, function(a, b)
    if a.copper ~= b.copper then return a.copper > b.copper end
    return a.label < b.label
  end)

  local coin = "|T" .. ns.COIN_ICON .. ":16|t "
  local lines = {
    string.format("%s|cffffd100Total gold received|r   %s", coin, ns.FormatMoney(total)),
    "    from every source below",
    " ",
    "|cffffd100By source|r",
  }
  for _, s in ipairs(sources) do
    lines[#lines + 1] = string.format("    %s   %s   (%.1f%%)", s.label, ns.FormatMoney(s.copper), 100 * s.copper / total)
  end

  local zl = {}
  for zone, n in pairs(zoneTotals) do zl[#zl + 1] = { zone = zone, copper = n } end
  table.sort(zl, function(a, b)
    if a.copper ~= b.copper then return a.copper > b.copper end
    return a.zone < b.zone
  end)
  if #zl > 0 then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd100By zone|r"
    for _, z in ipairs(zl) do
      lines[#lines + 1] = string.format("    %s   %s   (%.1f%%)", z.zone, ns.FormatMoney(z.copper), 100 * z.copper / total)
    end
  end
  return table.concat(lines, "\n")
end

-- Gold page, Vendor / Mail / Trades tabs: gold from one source, by zone.
-- Under each zone of the Vendor tab, the vendors you sold to.
local function GoldSourcePage(db, cat)
  local m = db.moneyIn and db.moneyIn[cat]
  if not (m and (m.total or 0) > 0) then
    return "No gold received from this source yet."
  end
  local coin = "|T" .. ns.COIN_ICON .. ":14|t "
  local lines = {
    string.format("%s|cffffd100Gold from %s|r   %s   (%d times)", coin, (MONEY_LABELS[cat] or cat):lower(), ns.FormatMoney(m.total), m.times or 0),
    " ",
  }
  local zones = {}
  for zone, n in pairs(m.zones or {}) do zones[#zones + 1] = { zone = zone, copper = n } end
  table.sort(zones, function(a, b)
    if a.copper ~= b.copper then return a.copper > b.copper end
    return a.zone < b.zone
  end)
  for _, z in ipairs(zones) do
    lines[#lines + 1] = string.format("|cff00ff00%s|r   %s", z.zone, ns.FormatMoney(z.copper))
    if cat == "Vendor" then
      local names = {}
      for vname, v in pairs((db.vendors and db.vendors[z.zone]) or {}) do
        if (v.sold or 0) > 0 then names[#names + 1] = { name = vname, copper = v.sold, times = v.soldTimes or 0 } end
      end
      table.sort(names, function(a, b)
        if a.copper ~= b.copper then return a.copper > b.copper end
        return a.name < b.name
      end)
      for _, v in ipairs(names) do
        lines[#lines + 1] = string.format("    %s   %s   (%d times)", v.name, ns.FormatMoney(v.copper), v.times)
      end
    end
    lines[#lines + 1] = " "
  end
  return table.concat(lines, "\n")
end

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
-- Does a quest match the text typed in the quest search box? (already lower case)
-- Matches the quest's name, its zone, or its level.
local function QuestMatches(q, text)
  if text == "" then return true end
  if (q.name or ""):lower():find(text, 1, true) then return true end
  if (q.zone or ""):lower():find(text, 1, true) then return true end
  if q.level and (tostring(q.level) == text or ("level " .. q.level) == text) then return true end
  return false
end

local function QuestsDonePage(db)
  local list, everything = {}, 0
  local search = ns.questSearch or ""
  for questID, q in pairs(db.quests or {}) do
    if q.t then   -- skip half-made records with no turn-in
      everything = everything + 1
      if QuestMatches(q, search) then list[#list + 1] = { id = questID, q = q } end
    end
  end
  if everything == 0 then
    return "No completed quests recorded yet. Turn in a quest and it will appear here."
  end
  if #list == 0 then return "No completed quest matches your search." end
  table.sort(list, function(a, b)
    if a.q.t ~= b.q.t then return a.q.t > b.q.t end
    return a.id < b.id
  end)

  local heading = (search ~= "") and string.format("|cffffd100%d of %d quests match|r", #list, everything)
                  or string.format("|cffffd100%d quests completed|r", #list)
  local lines = { heading, " " }
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

-- Quest Rewards page, third and fourth tabs: completed quests grouped by ZONE
-- or by LEVEL (the level you were when you turned them in). Every group shows
-- its totals: quests, XP, gold, and items earned.
local function QuestsGroupedPage(db, by)
  local all, everything = {}, 0
  local search = ns.questSearch or ""
  for questID, q in pairs(db.quests or {}) do
    if q.t then
      everything = everything + 1
      if QuestMatches(q, search) then all[#all + 1] = { id = questID, q = q } end
    end
  end
  if everything == 0 then
    return "No completed quests recorded yet. Turn in a quest and it will appear here."
  end
  if #all == 0 then return "No completed quest matches your search." end

  -- Number of reward items (counting stack sizes) of a quest
  local function itemCount(q)
    local n = 0
    for _, qty in pairs(q.rewards or {}) do n = n + qty end
    return n
  end

  -- Put each quest in its group and add up the group's totals
  local groups, keys = {}, {}
  local grand = { n = 0, xp = 0, money = 0, items = 0 }
  for _, e in ipairs(all) do
    local q = e.q
    local key
    if by == "zone" then key = q.zone or "Unknown zone" else key = q.level or 0 end
    local g = groups[key]
    if not g then g = { list = {}, xp = 0, money = 0, items = 0 }; groups[key] = g; keys[#keys + 1] = key end
    g.list[#g.list + 1] = e
    g.xp = g.xp + (q.xp or 0)
    g.money = g.money + (q.money or 0)
    g.items = g.items + itemCount(q)
    grand.n = grand.n + 1
    grand.xp = grand.xp + (q.xp or 0)
    grand.money = grand.money + (q.money or 0)
    grand.items = grand.items + itemCount(q)
  end
  -- Zone names A to Z. Levels with the HIGHEST first, so your newest quests are on top.
  if by == "zone" then
    table.sort(keys)
  else
    table.sort(keys, function(a, b) return a > b end)
  end

  -- "3 quests   |   620 XP   |   <gold>   |   2 items"
  local function totals(n, xp, money, items)
    return string.format("%d %s   |   %d XP   |   %s   |   %d %s",
      n, n == 1 and "quest" or "quests", xp, ns.FormatMoney(money), items, items == 1 and "item" or "items")
  end

  local lines = {
    "|cffffd100All completed quests|r",
    "    " .. totals(grand.n, grand.xp, grand.money, grand.items),
    " ",
  }
  for _, key in ipairs(keys) do
    local g = groups[key]
    local title
    if by == "zone" then title = key
    elseif key == 0 then title = "Level unknown"
    else title = "Level " .. key end
    lines[#lines + 1] = "|cff00ff00" .. title .. "|r"
    lines[#lines + 1] = "    " .. totals(#g.list, g.xp, g.money, g.items)

    -- Inside a zone: lowest level first. Inside a level: by zone. Then oldest first.
    table.sort(g.list, function(a, b)
      if by == "zone" then
        local la, lb = a.q.level or 0, b.q.level or 0
        if la ~= lb then return la < lb end
      else
        local za, zb = a.q.zone or "", b.q.zone or ""
        if za ~= zb then return za < zb end
      end
      if a.q.t ~= b.q.t then return a.q.t < b.q.t end
      return a.id < b.id
    end)
    for _, e in ipairs(g.list) do
      local q = e.q
      local where = (by == "zone") and ("level " .. (q.level or "?")) or (q.zone or "unknown zone")
      lines[#lines + 1] = string.format("        %s   %s   %s", q.name or "Unknown quest", where, ns.DateText(q.t))
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
  gold = {   -- Gold page: all gold received, or one source
    { key = "all",    label = "All gold" },
    { key = "looted", label = "Looted" },
    { key = "Vendor", label = "Vendors" },
    { key = "Mail",   label = "Mail" },
    { key = "Trades", label = "Trades" },
  },
  quest = {
    { key = "rewards",   label = "Rewards" },
    { key = "completed", label = "Completed" },
    { key = "byzone",    label = "By Zone" },
    { key = "bylevel",   label = "By Level" },
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
  { key = "Objects",   label = "Other objects (Treasure, Trash, Trinkets)", verb = "opened",   per = "object" },
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
    "                    for details and its loot. Right-click a card to mark a quest mob, change its designation",
    "                    (Elite, Rare, Boss, Critter), or mark it 'Not in game version'. Designations come from the creature list.",
    "  Mob Drops         for each creature: kills, drops, drop rates, and coin. Click the column headings to sort.",
    "                    Right-click a creature in the list to delete its data.",
    "  Fishing Log       everything that can be fished up, greyed out until caught. Stars for catches.",
    "  Quest Rewards     reward items, and a Completed Quests tab (date, level, XP).",
    "  Gold              all gold received (looted, vendors, mail, trades, quests) with tabs for each, and the creatures that pay best.",
    "  Gathering         mining, herbs, and skinning by zone and node.",
    "  Received Items    items from vendors (by vendor name), mail, crafting (by kind of crafting), and trades (with a trade log),",
    "                    and the gold you got from selling, mail, and trades. Sales also show under Mob Drops (gold made from items).",
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
    "  " .. C .. "/lootlog corrections|r           list creatures where the game showed something different from the creature list",
    "  " .. C .. "/lootlog debug|r                 print what the Hunting Log loaded and how many creatures it lists",
  }
  return table.concat(lines, "\n")
end

-- The list on the right of the Gathering page: everything you have gathered
-- in total, by kind of gathering (only the kinds you have done), added up over
-- all zones. Shown in the side panel (ns.SIDE_BUILDERS, used by UI.lua).
local function GatheringTotals(db)
  local lines = { "|cffffd100Total gathered|r", " " }
  local any = false
  for _, sec in ipairs(GATHER_SECTIONS) do
    local zones = db.events[sec.key]
    if zones and next(zones) ~= nil then
      -- Add each item up over every zone
      local totals, sum = {}, 0
      for _, items in pairs(zones) do
        for itemID, e in pairs(items) do
          totals[itemID] = (totals[itemID] or 0) + e.count
          sum = sum + e.count
        end
      end
      local list = {}
      for itemID, n in pairs(totals) do list[#list + 1] = { id = itemID, n = n } end
      table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.id < b.id
      end)
      if #list > 0 then
        any = true
        lines[#lines + 1] = string.format("|cff00ff00%s|r   %d", sec.label, sum)
        for _, it in ipairs(list) do
          local icon = ns.GetIcon(db, it.id)
          local pic = icon and ("|T" .. icon .. ":14|t ") or ""
          lines[#lines + 1] = string.format("  %s%s  x%d", pic, ns.ItemText(db, it.id), it.n)
        end
        lines[#lines + 1] = " "
      end
    end
  end
  if not any then return "|cffffd100Total gathered|r\n \nNothing gathered yet." end
  return table.concat(lines, "\n")
end

-- Pages that show a list on the right: page key -> function that builds its text
ns.SIDE_BUILDERS = { gathering = GatheringTotals }

-- Received Items, Crafting tab: what you made, separated by KIND of crafting
-- (Blacksmithing, Smelting, Cooking...). db.crafting[type][itemID] = quantity.
-- Items crafted before kinds were recorded are listed under "Kind not recorded".
local function CraftingPage(db)
  local crafting = db.crafting or {}
  local types = {}
  for t in pairs(crafting) do types[#types + 1] = t end
  table.sort(types)

  local function itemLine(itemID, qty)
    local icon = ns.GetIcon(db, itemID)
    local pic = icon and ("|T" .. icon .. ":14|t ") or ""
    return string.format("    %s%s [ID %d] x%d", pic, ns.ItemText(db, itemID), itemID, qty)
  end
  local function sorted(map)
    local list = {}
    for itemID, qty in pairs(map) do if qty > 0 then list[#list + 1] = { id = itemID, qty = qty } end end
    table.sort(list, function(a, b)
      if a.qty ~= b.qty then return a.qty > b.qty end
      return a.id < b.id
    end)
    return list
  end

  local lines, accounted = {}, {}
  for _, t in ipairs(types) do
    local list = sorted(crafting[t])
    local total = 0
    for _, e in ipairs(list) do total = total + e.qty; accounted[e.id] = (accounted[e.id] or 0) + e.qty end
    lines[#lines + 1] = string.format("|cffffd100%s|r - %d items", t, total)
    for _, e in ipairs(list) do lines[#lines + 1] = itemLine(e.id, e.qty) end
    lines[#lines + 1] = " "
  end

  -- Whatever the overall crafting log has beyond that was made before kinds were recorded
  local left = {}
  for _, items in pairs(db.events["Crafting"] or {}) do
    for itemID, e in pairs(items) do left[itemID] = (left[itemID] or 0) + e.count end
  end
  for itemID, n in pairs(accounted) do if left[itemID] then left[itemID] = left[itemID] - n end end
  local leftList = sorted(left)
  if #leftList > 0 then
    lines[#lines + 1] = "|cff999999Kind not recorded|r"
    for _, e in ipairs(leftList) do lines[#lines + 1] = itemLine(e.id, e.qty) end
  end
  if #lines == 0 then return "Nothing crafted yet." end
  return table.concat(lines, "\n")
end

-- Received Items, Trades tab: the usual list (gold and items received), then
-- a log of every trade: what you gave for what you got. db.trades is newest first.
local function TradesPage(db, base)
  local lines = {}
  if base then lines[#lines + 1] = base end

  local function side(items, gold)
    local parts = {}
    local ids = {}
    for itemID in pairs(items) do ids[#ids + 1] = itemID end
    table.sort(ids)
    for _, itemID in ipairs(ids) do
      parts[#parts + 1] = ns.ItemText(db, itemID) .. ((items[itemID] > 1) and (" x" .. items[itemID]) or "")
    end
    if gold and gold > 0 then parts[#parts + 1] = ns.FormatMoney(gold) end
    return #parts > 0 and table.concat(parts, ", ") or "nothing"
  end

  local trades = db.trades or {}
  if #trades > 0 then
    if #lines > 0 then lines[#lines + 1] = " " end
    lines[#lines + 1] = "|cffffd100Trade log|r   (newest first, the last 200 trades)"
    lines[#lines + 1] = " "
    local sortedTrades = {}
    for _, t in ipairs(trades) do sortedTrades[#sortedTrades + 1] = t end
    table.sort(sortedTrades, function(a, b) return a.t > b.t end)   -- (also right for the combined all-characters list)
    for _, t in ipairs(sortedTrades) do
      lines[#lines + 1] = string.format("|cff00ff00%s|r  with %s  (%s)", date("%Y-%m-%d %H:%M", t.t), t.partner or "?", t.zone or "?")
      lines[#lines + 1] = "    Gave:  " .. side(t.gave or {}, t.gaveGold)
      lines[#lines + 1] = "    Got:   " .. side(t.got or {}, t.gotGold)
      lines[#lines + 1] = " "
    end
  end
  if #lines == 0 then return "Nothing received in trades yet." end
  return table.concat(lines, "\n")
end

-- Received Items, Mail tab: items you sold at the auction house. Taking the
-- proceeds from an "Auction successful" mail credits the gold to the item.
local function AuctionLines(db)
  local list = {}
  for itemID, s in pairs(db.sales or {}) do
    if (s.aucCount or 0) > 0 then list[#list + 1] = { id = itemID, n = s.aucCount, gold = s.aucGold or 0 } end
  end
  if #list == 0 then return "" end
  table.sort(list, function(a, b)
    if a.gold ~= b.gold then return a.gold > b.gold end
    return a.id < b.id
  end)
  local lines = { "|cffffd100Sold at the auction house|r" }
  for _, e in ipairs(list) do
    local icon = ns.GetIcon(db, e.id)
    local pic = icon and ("|T" .. icon .. ":14|t ") or ""
    lines[#lines + 1] = string.format("    %s%s x%d   %s", pic, ns.ItemText(db, e.id), e.n, ns.FormatMoney(e.gold))
  end
  return table.concat(lines, "\n")
end

-- Vendor tab of the Received Items page: gold from selling and items bought,
-- by zone and then by VENDOR NAME. Totals for all vendors are at the top.
-- Data: db.vendors[zone][vendorName] = { sold, soldTimes, bought = { [itemID] = qty } }
-- (written by Capture.lua). Things logged before vendor names were recorded
-- are listed under "vendor not recorded".
local function VendorPage(db)
  local events = db.events["Vendor"] or {}
  local vendors = db.vendors or {}
  local money = db.moneyIn and db.moneyIn["Vendor"]
  local moneyZones = (money and money.zones) or {}
  local coin = "|T" .. ns.COIN_ICON .. ":14|t "

  -- Zones that have anything to show
  local zoneSet = {}
  for z in pairs(events) do zoneSet[z] = true end
  for z in pairs(vendors) do zoneSet[z] = true end
  for z in pairs(moneyZones) do zoneSet[z] = true end
  local zoneNames = {}
  for z in pairs(zoneSet) do zoneNames[#zoneNames + 1] = z end
  if #zoneNames == 0 then return "Nothing bought from or sold to vendors yet." end
  table.sort(zoneNames)

  -- One line for an item: picture, link, ID, quantity
  local function itemLine(itemID, qty, indent)
    local icon = ns.GetIcon(db, itemID)
    local pic = icon and ("|T" .. icon .. ":14|t ") or ""
    return string.format("%s%s%s [ID %d] x%d", indent, pic, ns.ItemText(db, itemID), itemID, qty)
  end

  -- A list of { id, qty } sorted by quantity, then by ID
  local function sortedItems(map)
    local list = {}
    for itemID, qty in pairs(map) do if qty > 0 then list[#list + 1] = { id = itemID, qty = qty } end end
    table.sort(list, function(a, b)
      if a.qty ~= b.qty then return a.qty > b.qty end
      return a.id < b.id
    end)
    return list
  end

  local lines = {}
  if money and (money.total or 0) > 0 then
    lines[#lines + 1] = string.format("%s|cffffd100Gold from selling to vendors|r   %s   (%d times)",
      coin, ns.FormatMoney(money.total), money.times or 0)
    lines[#lines + 1] = " "
  end

  for _, zone in ipairs(zoneNames) do
    lines[#lines + 1] = "|cffffd100" .. zone .. "|r"

    -- Each vendor in this zone, by name
    local names = {}
    for vname in pairs(vendors[zone] or {}) do names[#names + 1] = vname end
    table.sort(names)
    local soldTotal = 0
    local boughtTotal = {}    -- itemID -> quantity bought from named vendors
    for _, vname in ipairs(names) do
      local v = vendors[zone][vname]
      lines[#lines + 1] = "  |cff00ff00" .. vname .. "|r"
      if (v.sold or 0) > 0 then
        lines[#lines + 1] = string.format("    %sGold from selling to %s   %s   (%d times)",
          coin, vname, ns.FormatMoney(v.sold), v.soldTimes or 0)
        soldTotal = soldTotal + v.sold
      end
      -- The items you sold to this vendor, most valuable first
      local soldList = {}
      for itemID, si in pairs(v.soldItems or {}) do soldList[#soldList + 1] = { id = itemID, n = si.n, gold = si.gold } end
      table.sort(soldList, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return a.id < b.id
      end)
      if #soldList > 0 then
        lines[#lines + 1] = "    Sold to " .. vname .. ":"
        for _, it in ipairs(soldList) do
          local icon = ns.GetIcon(db, it.id)
          local pic = icon and ("|T" .. icon .. ":14|t ") or ""
          lines[#lines + 1] = string.format("        %s%s x%d   %s", pic, ns.ItemText(db, it.id), it.n, ns.FormatMoney(it.gold))
        end
      end
      local bought = sortedItems(v.bought or {})
      if #bought > 0 then
        lines[#lines + 1] = "    Bought from " .. vname .. ":"
        for _, it in ipairs(bought) do
          lines[#lines + 1] = itemLine(it.id, it.qty, "        ")
          boughtTotal[it.id] = (boughtTotal[it.id] or 0) + it.qty
        end
      end
    end

    -- Whatever is left of the zone's totals was logged before vendor names
    local leftGold = (moneyZones[zone] or 0) - soldTotal
    local leftItems = {}
    for itemID, e in pairs(events[zone] or {}) do
      local rest = e.count - (boughtTotal[itemID] or 0)
      if rest > 0 then leftItems[itemID] = rest end
    end
    local leftList = sortedItems(leftItems)
    if leftGold > 0 or #leftList > 0 then
      lines[#lines + 1] = "  |cff999999Vendor not recorded|r"
      if leftGold > 0 then
        lines[#lines + 1] = string.format("    %sGold from selling   %s", coin, ns.FormatMoney(leftGold))
      end
      if #leftList > 0 then
        lines[#lines + 1] = "    Bought:"
        for _, it in ipairs(leftList) do lines[#lines + 1] = itemLine(it.id, it.qty, "        ") end
      end
    end
    lines[#lines + 1] = " "
  end
  return table.concat(lines, "\n")
end

-- Page key -> function that returns that page's text.
-- "mobs" is not here because it has its own two-pane layout (PageMobs.lua).
ns.BUILDERS = {
  help      = function() return HelpPage() end,
  session   = SessionPage,
  quest     = function(db)
    local tab = ns.GetSubTab("quest")
    if tab == "completed" then return QuestsDonePage(db) end
    if tab == "byzone" then return QuestsGroupedPage(db, "zone") end
    if tab == "bylevel" then return QuestsGroupedPage(db, "level") end
    -- (no "% of zone" here: it does not mean much for quest rewards)
    return EventPage(db, "Quest", "No quest rewards recorded yet. Turn in a quest that gives an item.", { percent = false })
  end,
  gold      = function(db)
    local tab = ns.GetSubTab("gold")
    if tab == "looted" then return GoldPage(db) end
    if tab == "all" then return GoldAllPage(db) end
    return GoldSourcePage(db, tab)   -- Vendor / Mail / Trades
  end,
  gathering = GatheringPage,
  received  = function(db)
    -- The tab keys are the event categories Capture.lua logs under
    local tab = ns.GetSubTab("received")
    local empty = {
      ["Vendor"]         = "Nothing bought from or sold to vendors yet.",
      ["Mail"]           = "Nothing taken from your mailbox yet.",
      ["Crafting"]       = "Nothing crafted yet.",
      ["Trades"]         = "Nothing received in trades yet.",
      ["Other received"] = "Nothing else yet. Items that arrive without a loot window, a vendor, mail, a trade, or a craft are listed here.",
    }
    -- The Vendor tab names each vendor (see VendorPage above)
    if tab == "Vendor" then return VendorPage(db) end
    -- Mail and Trades also show the gold you received there
    local moneyLabels = {
      ["Vendor"] = "Gold from selling to vendors",
      ["Mail"]   = "Gold taken from mail",
      ["Trades"] = "Gold from trades",
    }
    if tab == "Crafting" then return CraftingPage(db) end   -- separated by kind of crafting
    local page = EventPage(db, tab, empty[tab], { money = db.moneyIn and db.moneyIn[tab], moneyLabel = moneyLabels[tab] })
    if tab == "Mail" then
      local extra = AuctionLines(db)                         -- items sold at the auction house
      if extra ~= "" then page = (page == empty[tab] and "" or (page .. "\n \n")) .. extra end
    elseif tab == "Trades" then
      return TradesPage(db, page ~= empty[tab] and page or nil)   -- adds the trade log
    end
    return page
  end,
}
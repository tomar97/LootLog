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
    for itemID, e in pairs(zones[zone]) do
      lines[#lines + 1] = string.format("    %s [ID %d] x%d   (%.1f%% of zone)",
        ns.ItemText(db, itemID, e.name), itemID, e.count, 100 * e.count / math.max(total, 1))
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

-- Page key -> function that returns that page's text.
-- "mobs" is not here because it has its own two-pane layout (PageMobs.lua).
ns.BUILDERS = {
  fishing   = function(db) return EventPage(db, "Fishing", "No fishing loot recorded yet.") end,
  quest     = function(db) return EventPage(db, "Quest", "No quest rewards recorded yet. Quest capture is not built.") end,
  gold      = GoldPage,
  gathering = function(db) return EventPage(db, "Objects", "No gathering recorded yet.") end,
}
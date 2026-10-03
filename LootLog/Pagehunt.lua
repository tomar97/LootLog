--[[
=====================================================================
 PageHunt.lua - the Hunting Log (grid of creature cards + detail page)
=====================================================================
 TWO VIEWS inside this page:
   List view    a grid of creature cards (the default)
   Detail view  one creature: big model, stars, info, and its loot.
                Opened by LEFT-clicking a card, closed with "Back".

 Each card shows:
   - a 3D model of the creature (looked up by its NPC ID)
   - its name, a class tag in the top-left (Elite / Rare / Boss /
     Critter / Quest) and "Unseen" in the top-right if you have not met it
   - at the bottom: faction badges, and three star slots
 A card is GREYED OUT until you kill that creature once.
 RIGHT-click a card to set its class (Normal / Elite / Rare / Boss /
 Critter / Quest). The same menu has a button to mark a creature "Not in
 game version": it disappears from the list but stays in your saved data.
 To see or restore those, use Show > Not in version.

 FACTION BADGES (bottom-left of each card):
   yellow A = neutral to the Alliance     red A = hostile to the Alliance
   yellow H = neutral to the Horde        red H = hostile to the Horde
 A creature can show both letters. They come from the starter lists
 (Seed_*.lua) and from what the game reports when you meet a creature.

 STARS (kill counts come from ns.HUNT_TIERS_BY_CLASS in Core.lua):
   Normal / Quest   10 / 50 / 100 kills
   Elite/Rare/Boss  1 / 5 / 10 kills
   Critter          1 star for SEEING it, 2 for killing one, 3 for killing 5

 CONTROLS (top bar of the list view):
   Zone       drop-down: Current zone (follows you), All zones, or a zone
   Type       drop-down: Creatures / Critters / All types
   Show       drop-down: All / Seen / Unseen / Not in version
   Prev / Next   page through the grid

 SEEN vs UNSEEN:
   Seen    you met it in game (targeted, moused over, or looted it)
   Unseen  it is only in a starter list (Seed_*.lua)
 All starter creatures load from the start (see ns.ONLY_VISITED_ZONES in
 Core.lua to change that).

 WHERE THE CREATURE LIST COMES FROM:
   ns.SeedCreatures  starter lists loaded from the Seed_*.lua files
   db.known          creatures you targeted or moused over
   db.mobs           creatures you have looted (kill counts live here)
 filtered by zone, type, Seen filter, and the faction log being viewed.

 KILL COUNTS come from db.mobs[npcID].kills, so they only count kills
 where a loot window opened. See "Known limits" in TODO.md.

 Exposes functions on ns for other files:
   ns.CreateHuntPanel(ui)  builds the frames, called once
   ns.RefreshHunt(db)      fills them with current data on every redraw
   ns.HuntDebug()          prints diagnostics (/lootlog debug)
=====================================================================
]]

local ADDON, ns = ...

-- ===== GRID LAYOUT (pixels) =====
local COLS, ROWS = 5, 3
local PER_PAGE = COLS * ROWS      -- cards per page (15)
local CARD_W, CARD_H = 130, 128
local STEP_X, STEP_Y = 138, 134   -- distance between card corners (card size + gap)

local STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"  -- built-in yellow star

local cards = {}        -- the 15 card frames, created once in ns.CreateHuntPanel
local detailRows = {}   -- pool of loot rows on the detail page

-- Special zone choice meaning "whatever zone I am standing in right now"
local CURRENT = "@current"

-- Popup menus (built the first time they are needed, further down)
local classMenu
local zoneMenu
local choiceMenu

-- Choices for the Type and Show drop-downs
local VIEW_CHOICES = {
  { key = "creatures", label = "Creatures" },
  { key = "critters",  label = "Critters" },
  { key = "all",       label = "All types" },
}
local SEEN_CHOICES = {
  { key = "all",    label = "All" },
  { key = "seen",   label = "Seen" },
  { key = "unseen", label = "Unseen" },
  -- creatures you marked "Not in game version" (hidden from every other list)
  { key = "removed", label = "Not in version", short = "Removed" },
}

-- Finds the label for a key in a choices list (used for the button text)
local function LabelFor(choices, key)
  for _, c in ipairs(choices) do
    if c.key == key then return c.short or c.label end   -- short text fits the button
  end
  return choices[1].short or choices[1].label
end

-- Colors for the class tag (red, green, blue)
local CLASS_COLORS = {
  elite   = { 1, 0.82, 0 },
  rare    = { 0.7, 0.85, 1 },
  boss    = { 1, 0.3, 0.3 },
  critter = { 0.6, 1, 0.6 },
  quest   = { 1, 0.6, 0.2 },
}

-- Faction badge colors and names
local HOST_COLOR = {
  neutral = { 1, 0.85, 0.1 },   -- yellow
  hostile = { 1, 0.15, 0.15 },  -- red
}
local FACTION_NAME = { A = "Alliance", H = "Horde" }


-- =====================================================================
-- HELPERS
-- =====================================================================

-- Hides every popup menu (used before opening one and when leaving the page)
local function CloseMenus()
  if classMenu then classMenu:Hide() end
  if zoneMenu then zoneMenu:Hide() end
  if choiceMenu then choiceMenu:Hide() end
end

-- The name of the zone you are standing in (for the "Current zone" option)
local function CurrentZoneLabel()
  local zone = GetRealZoneText()
  if zone and zone ~= "" then return zone end
  return "unknown"
end

-- Cuts long text so it fits a button, adding "..."
local function Shorten(text, max)
  if #text > max then return text:sub(1, max - 3) .. "..." end
  return text
end

-- How many stars a kill count has earned (0 to 3) for a creature class.
-- seen = true if you have met the creature (critters earn a star for that).
local function StarsFor(kills, class, seen)
  local n = 0
  if class == "critter" and seen then n = 1 end   -- first critter star = seeing it
  for _, tier in ipairs(ns.TiersFor(class)) do
    if kills >= tier then n = n + 1 end
  end
  return n
end

-- Text telling you how to earn the next star, or nil if all are earned.
local function NextStarText(kills, class, seen)
  if class == "critter" and not seen then return "See it for its first star" end
  for _, tier in ipairs(ns.TiersFor(class)) do
    if kills < tier then return "Next star at " .. tier .. " kills" end
  end
  return nil
end

-- Lights up (or dims) a row of three star textures to match a star count.
local function SetStars(textures, count)
  for s = 1, 3 do
    local t = textures[s]
    if s <= count then
      t:SetDesaturated(false)
      t:SetAlpha(1)
    else
      t:SetDesaturated(true)
      t:SetAlpha(0.3)
    end
  end
end

-- Turns a set of zone names ({ ["Durotar"] = true, ... }) into a short
-- text: up to 3 names, then "+N more". Returns nil if empty.
local function ZonesText(zset)
  local z = {}
  for name in pairs(zset) do z[#z + 1] = name end
  table.sort(z)
  if #z == 0 then return nil end
  local shown = {}
  for i = 1, math.min(#z, 3) do shown[i] = z[i] end
  local text = table.concat(shown, ", ")
  if #z > 3 then text = text .. string.format(" +%d more", #z - 3) end
  return text
end

-- One creature's drops as a list of { id, it }, most common first.
local function SortedDrops(m)
  local drops = {}
  for itemID, it in pairs(m.items) do drops[#drops + 1] = { id = itemID, it = it } end
  table.sort(drops, function(a, b)
    if a.it.drops ~= b.it.drops then return a.it.drops > b.it.drops end
    return a.id < b.id
  end)
  return drops
end

-- Does a creature record belong to the chosen zone?
-- choice is "All", CURRENT (the zone or sub-zone you are in), or a zone name.
local function ZoneMatches(r, choice, places)
  if choice == "All" then return true end
  if choice == CURRENT then
    for _, p in ipairs(places) do
      if r.zones[p] then return true end
    end
    return false
  end
  return r.zones[choice] == true
end

-- Fills one card with one creature's data.
-- e = { id, name, kills, class, crit, where, seen, host }
local function FillCard(card, e)
  card.entry = e   -- the tooltip, click, and right-click menu read this
  local unlocked = e.kills > 0

  -- Only reload the 3D model when the creature actually changed.
  -- pcall = "protected call": if the client rejects this ID, we skip it
  -- instead of throwing an error that breaks the whole page.
  if card.modelNpc ~= e.id then
    card.model:ClearModel()
    pcall(card.model.SetCreature, card.model, e.id)
    card.modelNpc = e.id
  end

  card.shade:SetShown(not unlocked)   -- dark overlay = "greyed out"
  card.name:SetText(e.name)

  -- Top-left tag: the class, if it has one (blank for normal)
  if e.class ~= "normal" then
    card.tag:SetText(ns.CLASS_LABELS[e.class])
    local c = CLASS_COLORS[e.class] or { 1, 1, 1 }
    card.tag:SetTextColor(c[1], c[2], c[3])
  else
    card.tag:SetText("")
  end

  -- Top-right tag: "Unseen" for a creature you have not met yet
  if e.removed then
    card.tag2:SetText("Removed")
    card.tag2:SetTextColor(1, 0.3, 0.3)
  else
    card.tag2:SetText(e.seen and "" or "Unseen")
    card.tag2:SetTextColor(0.7, 0.7, 0.7)
  end

  if unlocked then
    card.name:SetTextColor(1, 0.82, 0)         -- gold
  else
    card.name:SetTextColor(0.55, 0.55, 0.55)   -- grey
  end

  -- Faction badges: show a letter only when we know how that faction is treated
  for letter, fs in pairs(card.badges) do
    local state = e.host and e.host[letter]
    if state then
      local c = HOST_COLOR[state]
      fs:SetTextColor(c[1], c[2], c[3])
      fs:Show()
    else
      fs:Hide()
    end
  end

  SetStars(card.stars, StarsFor(e.kills, e.class, e.seen))
end


-- =====================================================================
-- BUILDING THE LIST OF CREATURES TO SHOW
-- =====================================================================

-- Returns: entries (the creatures to show, sorted by name),
--          killed (how many of them have been killed),
--          zoneList (zones to offer in the zone menu: CURRENT, "All", then names).
-- s is the settings table (ns.Settings()): s.huntZone, s.huntView, s.huntSeen.
local function BuildEntries(db, s)
  local myFac = ns.ViewFaction()   -- "A", "H", or nil (nil = show every faction)

  -- Places you have been: recorded visits plus anywhere you have seen or
  -- killed something. Only used when ns.ONLY_VISITED_ZONES is true.
  local visited = {}
  for place in pairs(db.visited or {}) do visited[place] = true end

  -- One record per creature ID:
  --   info[id] = { name, zones = {set}, crit = bool, seen = bool,
  --                fac = {A=true,H=true} or nil,      which logs it shows in
  --                host = {A="neutral", H="hostile"}  how each faction is treated }
  local info = {}
  -- Finds the record for an ID, creating an empty one the first time.
  local function rec(id)
    local r = info[id]
    if not r then r = { zones = {}, host = {}, seen = false }; info[id] = r end
    return r
  end

  -- Source 1: creatures you have seen in game (db.known).
  for id in pairs(db.known or {}) do
    local k = ns.GetKnown(db, id)   -- also upgrades old name-only entries
    local r = rec(id)
    r.seen = true
    r.name = k.name or r.name
    r.crit = r.crit or ns.IsCritterType(k.ctype)
    for z in pairs(k.zones or {}) do      -- copy, don't alias the saved table
      r.zones[z] = true
      visited[z] = true
    end
    if k.fac then                   -- no faction data = leave the faction unchanged
      r.fac = r.fac or {}
      for letter in pairs(k.fac) do r.fac[letter] = true end
    end
    for letter, state in pairs(k.host or {}) do r.host[letter] = state end
  end

  -- Source 2: creatures you have looted (db.mobs).
  for id, m in pairs(db.mobs) do
    local r = rec(id)
    r.seen = true
    r.name = m.name or r.name
    if m.zones then
      for z in pairs(m.zones) do r.zones[z] = true; visited[z] = true end
    elseif m.zone then
      r.zones[m.zone] = true
      visited[m.zone] = true
    end
  end

  -- Source 3: starter lists (Seed_*.lua).
  --   c.fac is "A", "H", or "AH" (which logs it shows in)
  --   c.host is "neutral" or "hostile" toward those factions
  -- By default every starter creature loads, in every zone it belongs to.
  -- If ns.ONLY_VISITED_ZONES is true (Core.lua), a starter creature only
  -- loads for zones you have been to.
  for _, c in ipairs(ns.SeedCreatures or {}) do
    local hit = {}
    for _, z in ipairs(c.zones) do
      if (not ns.ONLY_VISITED_ZONES) or visited[z] then hit[#hit + 1] = z end
    end
    if info[c.id] or #hit > 0 or not ns.ONLY_VISITED_ZONES then
      local r = rec(c.id)
      r.name = r.name or c.name
      r.crit = r.crit or ns.IsCritterType(c.ctype)
      for _, z in ipairs(hit) do r.zones[z] = true end
      r.fac = r.fac or {}
      for letter in c.fac:gmatch(".") do   -- "AH" sets both
        r.fac[letter] = true
        -- what you saw in game wins over the starter list
        if c.host and not r.host[letter] then r.host[letter] = c.host end
      end
    end
  end

  -- Pass 1: keep creatures that belong to the faction log being viewed,
  -- and collect their zones for the zone menu. (No faction data = show.)
  local candidates, zoneSet = {}, {}
  for id, r in pairs(info) do
    if (not r.fac) or (not myFac) or (r.fac[myFac] == true) then
      candidates[#candidates + 1] = id
      -- zones of creatures marked "not in game version" are not offered
      -- (unless you are viewing that list)
      if s.huntSeen == "removed" or not ns.IsNotInGame(db, id) then
        for z in pairs(r.zones) do zoneSet[z] = true end
      end
    end
  end
  local zoneList = {}
  for z in pairs(zoneSet) do zoneList[#zoneList + 1] = z end
  table.sort(zoneList)
  table.insert(zoneList, 1, "All")
  table.insert(zoneList, 1, CURRENT)   -- "Current zone" goes at the very top

  -- If the saved zone is no longer available, go back to All.
  if s.huntZone ~= "All" and s.huntZone ~= CURRENT and not zoneSet[s.huntZone] then
    s.huntZone = "All"
  end
  local places = (s.huntZone == CURRENT) and ns.CurrentPlaces() or {}

  -- Pass 2: apply the zone, Type, and Seen filters.
  local entries, killed = {}, 0
  local wantCritters = (s.huntView == "critters")
  for _, id in ipairs(candidates) do
    local r = info[id]
    local class = ns.GetClass(db, id, r.crit)   -- your choice, else critter/game default
    local isCritter = (class == "critter")
    local viewOK = (s.huntView == "all") or (wantCritters == isCritter)
    local zoneOK = ZoneMatches(r, s.huntZone, places)
    local gone = ns.IsNotInGame(db, id)   -- marked "not in game version"
    local seenOK
    if s.huntSeen == "removed" then
      seenOK = gone                       -- the "Not in version" list shows only those
    else
      seenOK = (not gone) and ((s.huntSeen == "all")
                   or (s.huntSeen == "seen" and r.seen)
                   or (s.huntSeen == "unseen" and not r.seen))
    end
    if viewOK and zoneOK and seenOK then
      local m = db.mobs[id]
      local kills = m and m.kills or 0
      if kills > 0 then killed = killed + 1 end
      entries[#entries + 1] = {
        id = id,
        name = r.name or ("ID " .. id),
        kills = kills,
        class = class,
        crit = r.crit,
        where = ZonesText(r.zones),
        seen = r.seen,
        host = r.host,
        removed = gone,
      }
    end
  end
  table.sort(entries, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)

  return entries, killed, zoneList
end


-- =====================================================================
-- DEBUG: /lootlog debug
-- =====================================================================
-- Prints what the Hunting Log has loaded and how many creatures it would
-- list, to find out why a list is empty.
function ns.HuntDebug()
  local db = ns.DB()
  local s = ns.Settings()
  local seed = ns.SeedCreatures and #ns.SeedCreatures or 0
  local zones = 0
  for _ in pairs(ns.ZONE_NAME or {}) do zones = zones + 1 end
  local viewing = ns.ViewFaction()   -- the faction whose log is showing

  print(string.format("LootLog debug: starter creatures loaded: %d | zones loaded: %d | your faction: %s | viewing log: %s",
    seed, zones, tostring(ns.PlayerFaction()), tostring(viewing or "all")))
  if seed == 0 then
    print("  -> The starter list did not load. Check Seed_A_Neutral.lua is in the LootLog folder AND listed in LootLog.toc.")
  end
  if zones == 0 then
    print("  -> The zone list did not load. Check ZoneData.lua is in the LootLog folder AND listed in LootLog.toc.")
  end
  print(string.format("  your settings: zone=%s  type=%s  show=%s", s.huntZone, s.huntView, s.huntSeen))
  local gone = 0
  for _ in pairs(db.notInGame or {}) do gone = gone + 1 end
  if gone > 0 then print(string.format("  %d creatures are marked 'not in game version' (Show > Not in version).", gone)) end

  -- How many creatures each type would list with every filter wide open
  for _, view in ipairs({ "creatures", "critters" }) do
    local entries = BuildEntries(db, { huntZone = "All", huntView = view, huntSeen = "all" })
    local unseen = 0
    for _, e in ipairs(entries) do
      if not e.seen then unseen = unseen + 1 end
    end
    print(string.format("  %s, all zones: %d total, %d unseen", view, #entries, unseen))
  end

  -- Starter creatures that belong to the other faction's log are hidden
  local hidden = 0
  for _, c in ipairs(ns.SeedCreatures or {}) do
    if viewing and not c.fac:find(viewing, 1, true) then hidden = hidden + 1 end
  end
  if hidden > 0 then
    print(string.format("  %d starter creatures are hidden because they belong to the other faction's log. (/lootlog faction A, H, all, or mine to change which log shows.)", hidden))
  end
end


-- =====================================================================
-- DETAIL PAGE (click a card)
-- =====================================================================

-- One row in the detail page's loot list. i = row number (1 = top).
local function GetDetailRow(i)
  local r = detailRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, ns.ui.huntLootContent)
  r:SetSize(640, 20)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
  r:EnableMouse(true)               -- needed so the row receives hover events
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 0, 0)
  -- Helper that makes one text column at x pixels from the left, w wide.
  -- These x positions must match the headings in ns.CreateHuntPanel.
  local function fs(x, w)
    local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f:SetPoint("LEFT", x, 0)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
  end
  r.name = fs(22, 270)
  r.id   = fs(298, 60)
  r.qty  = fs(364, 50)
  r.rate = fs(420, 200)
  r:SetScript("OnEnter", function(self)
    if self.link then
      -- an item row: show the item tooltip
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.link)
      GameTooltip:Show()
    elseif self.tipLines then
      -- the coin row: show the lines built by ns.CoinTipLines (title first)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      for i, line in ipairs(self.tipLines) do
        if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1) end
      end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  detailRows[i] = r
  return r
end

-- Fills the detail page for the creature in ns.huntDetailEntry.
-- Name, zones, and faction info come from the entry saved when you clicked
-- the card; kills, class, and loot are read fresh so they stay current.
local function RefreshDetail(db)
  local ui = ns.ui
  local e = ns.huntDetailEntry
  local m = db.mobs[e.id]
  local kills = m and m.kills or 0
  local class = ns.GetClass(db, e.id, e.crit)
  local seen = e.seen or kills > 0

  -- 3D model (only reloaded when the creature changed)
  if ui.huntDetailModel.npc ~= e.id then
    ui.huntDetailModel:ClearModel()
    pcall(ui.huntDetailModel.SetCreature, ui.huntDetailModel, e.id)
    ui.huntDetailModel.npc = e.id
  end

  ui.huntDetailTitle:SetText(e.name)

  -- Info block to the right of the model.
  -- (A creature description will go here later.)
  local lines = { "ID " .. e.id }
  if class ~= "normal" then lines[#lines + 1] = ns.CLASS_LABELS[class] end
  if not seen then lines[#lines + 1] = "Not met yet (starter list)" end
  if ns.IsNotInGame(db, e.id) then lines[#lines + 1] = "Marked: not in game version" end
  for _, letter in ipairs({ "A", "H" }) do
    local state = e.host and e.host[letter]
    if state then lines[#lines + 1] = FACTION_NAME[letter] .. ": " .. state end
  end
  if e.where then lines[#lines + 1] = "Zones: " .. e.where end
  lines[#lines + 1] = (kills > 0) and ("Kills: " .. kills) or "Not killed yet"
  lines[#lines + 1] = NextStarText(kills, class, seen) or "All stars earned"
  ui.huntDetailInfo:SetText(table.concat(lines, "\n"))

  SetStars(ui.huntDetailStars, StarsFor(kills, class, seen))

  -- Loot list. Row 1 is the coin row (gold coin picture) when this creature
  -- has dropped any coin; the items follow it.
  local drops = m and SortedDrops(m) or {}
  local killsForRate = math.max(kills, 1)   -- avoid dividing by zero
  local hasCoin = m and m.gold and m.gold > 0
  local first = hasCoin and 1 or 0          -- how many rows come before the items
  if hasCoin then
    local r = GetDetailRow(1)
    local coinDrops = m.goldDrops or 0
    r.link = nil
    r.tipLines = ns.CoinTipLines(m, kills)  -- hover text for the coin row
    r.icon:SetTexture(ns.COIN_ICON)
    r.name:SetText("Coin  " .. ns.FormatMoney(m.gold))
    r.id:SetText("-")
    r.qty:SetText("")
    r.rate:SetText(string.format("%d/%d (%.1f%%)", coinDrops, killsForRate, 100 * coinDrops / killsForRate))
    r:Show()
  end
  for i, d in ipairs(drops) do
    local r = GetDetailRow(i + first)
    local link = db.items and db.items[d.id]
    r.link = link                       -- used by the hover tooltip
    r.tipLines = nil                    -- (only the coin row uses this)
    r.icon:SetTexture(ns.GetIcon(db, d.id))
    r.name:SetText(link or ("item:" .. d.id))
    r.id:SetText(d.id)
    r.qty:SetText("x" .. d.it.qty)
    r.rate:SetText(string.format("%d/%d (%.1f%%)", d.it.drops, killsForRate, 100 * d.it.drops / killsForRate))
    r:Show()
  end
  for i = #drops + first + 1, #detailRows do detailRows[i]:Hide() end
  ui.huntLootContent:SetHeight(math.max((#drops + first) * 20, 1))   -- lets the scrollbar work
  ui.huntLootEmpty:SetShown(#drops + first == 0)
end


-- =====================================================================
-- REFRESH
-- =====================================================================

function ns.RefreshHunt(db)
  local ui = ns.ui
  local s = ns.Settings()

  -- Detail view or list view?
  local inDetail = (ns.huntDetailEntry ~= nil)
  ui.huntList:SetShown(not inDetail)
  ui.huntDetail:SetShown(inDetail)
  if inDetail then
    CloseMenus()
    RefreshDetail(db)
    return
  end

  local entries, killed, zoneList = BuildEntries(db, s)
  ns.huntZones = zoneList   -- the zone menu reads this

  -- Remind you in the window title when you are not viewing your own
  -- faction's log (ns.Refresh in UI.lua resets the title for other pages).
  if ui.TitleText and s.huntFaction ~= "mine" then
    local names = { A = "Alliance", H = "Horde", all = "all factions" }
    ui.TitleText:SetText("LootLog - viewing " .. (names[s.huntFaction] or "?") .. " log")
  end

  -- Pagination: keep the page number inside the valid range
  local pages = math.max(1, math.ceil(#entries / PER_PAGE))
  ns.huntPage = math.min(math.max(ns.huntPage, 1), pages)
  local first = (ns.huntPage - 1) * PER_PAGE

  -- Fill the 15 cards; hide the unused ones on the last page
  for i = 1, PER_PAGE do
    local e = entries[first + i]
    if e then
      FillCard(cards[i], e)
      cards[i]:Show()
    else
      cards[i]:Hide()
    end
  end

  -- Top bar: button texts, summary, paging
  local zoneText
  if s.huntZone == "All" then
    zoneText = "All zones"
  elseif s.huntZone == CURRENT then
    zoneText = "Current (" .. CurrentZoneLabel() .. ")"
  else
    zoneText = s.huntZone
  end
  ui.huntZoneBtn:SetText(Shorten("Zone: " .. zoneText, 26))
  ui.huntViewBtn:SetText(LabelFor(VIEW_CHOICES, s.huntView))
  ui.huntSeenBtn:SetText("Show: " .. LabelFor(SEEN_CHOICES, s.huntSeen))
  ui.huntSummary:SetText(string.format("Killed %d / %d", killed, #entries))
  ui.huntPageText:SetText(string.format("Page %d / %d", ns.huntPage, pages))
  ui.huntPrev:SetEnabled(ns.huntPage > 1)
  ui.huntNext:SetEnabled(ns.huntPage < pages)

  -- Message when there is nothing to show
  ui.huntEmpty:SetShown(#entries == 0)
end


-- =====================================================================
-- POPUP MENUS
-- =====================================================================

-- ----- Class menu (right-click a card) -----
-- Lets you set a creature's class. Saved through ns.SetClass (Core.lua),
-- so it survives reloads and /lootlog reset.
-- To hand the choices to Claude later, upload your SavedVariables file
-- (WTF\Account\<ACCOUNT>\SavedVariables\LootLog.lua); the choices are in
-- its "classes" table.
local CLASS_CHOICES = { "normal", "elite", "rare", "boss", "critter", "quest" }

local function ShowClassMenu(card)
  CloseMenus()
  if not classMenu then
    classMenu = CreateFrame("Frame", "LootLogClassMenu", UIParent)
    classMenu:SetSize(160, 200)
    classMenu:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the main window
    classMenu:EnableMouse(true)                     -- so clicks don't pass through
    local bg = classMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    classMenu.title = classMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classMenu.title:SetPoint("TOP", 0, -6)
    classMenu.title:SetWidth(152)
    classMenu.title:SetWordWrap(false)
    -- One button per class
    for i, class in ipairs(CLASS_CHOICES) do
      local b = CreateFrame("Button", nil, classMenu, "UIPanelButtonTemplate")
      b:SetSize(148, 22)
      b:SetPoint("TOP", 0, -22 - (i - 1) * 24)
      b:SetText(ns.CLASS_LABELS[class])
      b:SetScript("OnClick", function()
        ns.SetClass(classMenu.npcID, class)   -- save the choice
        classMenu:Hide()
        ns.Refresh()                          -- redraw cards with new tag and stars
      end)
    end
    -- Separate button at the bottom: mark / restore "not in game version".
    -- Its text is set each time the menu opens (see below).
    local rb = CreateFrame("Button", nil, classMenu, "UIPanelButtonTemplate")
    rb:SetSize(148, 22)
    rb:SetPoint("TOP", 0, -22 - #CLASS_CHOICES * 24 - 6)
    rb:SetScript("OnClick", function()
      ns.SetNotInGame(classMenu.npcID, not classMenu.removed)   -- flip the flag
      classMenu:Hide()
      ns.Refresh()                                              -- the creature leaves (or returns to) the list
    end)
    classMenu.removedBtn = rb
    tinsert(UISpecialFrames, "LootLogClassMenu")   -- Esc closes it
    classMenu:Hide()
  end
  classMenu.npcID = card.entry.id
  classMenu.removed = card.entry.removed
  classMenu.removedBtn:SetText(card.entry.removed and "Back in game version" or "Not in game version")
  classMenu.title:SetText(card.entry.name)
  classMenu:ClearAllPoints()
  classMenu:SetPoint("TOPLEFT", card, "TOPRIGHT", 2, 0)   -- opens beside the card
  classMenu:Show()
end

-- ----- Zone menu (drop-down under the Zone button) -----
-- A scrolling list: "Current zone" first, then "All zones", then every zone
-- available. The list comes from ns.huntZones, which RefreshHunt fills in.
local zoneRows = {}        -- pool of reusable row buttons
local ZONE_ROW_H = 20

local function ShowZoneMenu(anchor)
  if not zoneMenu then
    zoneMenu = CreateFrame("Frame", "LootLogZoneMenu", UIParent)
    zoneMenu:SetSize(236, 320)
    zoneMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    zoneMenu:EnableMouse(true)
    local bg = zoneMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    local sf = CreateFrame("ScrollFrame", nil, zoneMenu, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(200, 10)
    sf:SetScrollChild(content)
    zoneMenu.content = content
    tinsert(UISpecialFrames, "LootLogZoneMenu")   -- Esc closes it
    zoneMenu:Hide()
  end

  -- Fill one row per zone (rows are reused, extras are hidden)
  local list = ns.huntZones or { CURRENT, "All" }
  local selected = ns.Settings().huntZone
  for i, z in ipairs(list) do
    local b = zoneRows[i]
    if not b then
      b = CreateFrame("Button", nil, zoneMenu.content)
      b:SetSize(200, ZONE_ROW_H)
      b:SetPoint("TOPLEFT", 0, -(i - 1) * ZONE_ROW_H)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")   -- mouse-over highlight
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.12)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      b.text:SetPoint("LEFT", 4, 0)
      b.text:SetWidth(192)
      b.text:SetJustifyH("LEFT")
      b.text:SetWordWrap(false)
      b:SetScript("OnClick", function(self)
        ns.Settings().huntZone = self.zone   -- saved with your settings
        ns.huntPage = 1                      -- start at the first page of the new zone
        zoneMenu:Hide()
        ns.Refresh()
      end)
      zoneRows[i] = b
    end
    b.zone = z
    if z == CURRENT then
      b.text:SetText("Current zone: " .. CurrentZoneLabel())
    elseif z == "All" then
      b.text:SetText("All zones")
    else
      b.text:SetText(z)
    end
    if z == selected then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(1, 1, 1) end
    b:Show()
  end
  for i = #list + 1, #zoneRows do zoneRows[i]:Hide() end
  zoneMenu.content:SetHeight(math.max(#list * ZONE_ROW_H, 1))   -- lets the scrollbar work

  zoneMenu:ClearAllPoints()
  zoneMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)   -- opens under the button
  zoneMenu:Show()
end

-- ----- Small drop-down used by the Type and Show buttons -----
-- choices = { { key = "...", label = "..." }, ... }
-- current = the key that is selected now (shown in gold)
-- onPick  = function(key) called when a row is clicked
-- Clicking the same button again closes the menu.
local CHOICE_ROW_H = 20
local choiceRows = {}

local function ShowChoiceMenu(anchor, choices, current, onPick)
  if choiceMenu and choiceMenu:IsShown() and choiceMenu.anchor == anchor then
    choiceMenu:Hide()
    return
  end
  CloseMenus()
  if not choiceMenu then
    choiceMenu = CreateFrame("Frame", "LootLogChoiceMenu", UIParent)
    choiceMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    choiceMenu:EnableMouse(true)
    local bg = choiceMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    tinsert(UISpecialFrames, "LootLogChoiceMenu")   -- Esc closes it
    choiceMenu:Hide()
  end
  choiceMenu.anchor = anchor
  choiceMenu.onPick = onPick
  choiceMenu:SetSize(130, #choices * CHOICE_ROW_H + 8)

  for i, c in ipairs(choices) do
    local b = choiceRows[i]
    if not b then
      b = CreateFrame("Button", nil, choiceMenu)
      b:SetSize(122, CHOICE_ROW_H)
      b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * CHOICE_ROW_H)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")   -- mouse-over highlight
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.12)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      b.text:SetPoint("LEFT", 6, 0)
      b:SetScript("OnClick", function(self)
        local pick = choiceMenu.onPick
        choiceMenu:Hide()
        pick(self.key)
      end)
      choiceRows[i] = b
    end
    b.key = c.key
    b.text:SetText(c.label)
    if c.key == current then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(1, 1, 1) end
    b:Show()
  end
  for i = #choices + 1, #choiceRows do choiceRows[i]:Hide() end

  choiceMenu:ClearAllPoints()
  choiceMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)   -- opens under the button
  choiceMenu:Show()
end


-- =====================================================================
-- FRAME CONSTRUCTION
-- =====================================================================

-- Builds one card (called 15 times).
-- Draw order matters for 3D models: a model is its own frame, so anything
-- that must appear ON TOP of it (the grey overlay, the corner tags) has to
-- be a separate frame with a higher frame level, not a texture on the card.
local function CreateCard(parent, index)
  local card = CreateFrame("Frame", nil, parent)
  card:SetSize(CARD_W, CARD_H)
  local col = (index - 1) % COLS          -- 0-based column
  local row = math.floor((index - 1) / COLS)   -- 0-based row
  card:SetPoint("TOPLEFT", 4 + col * STEP_X, -4 - row * STEP_Y)
  card:EnableMouse(true)                  -- so hovering and clicking work

  -- Dark card background
  card.bg = card:CreateTexture(nil, "BACKGROUND")
  card.bg:SetAllPoints()
  card.bg:SetColorTexture(0, 0, 0, 0.35)

  -- The 3D creature model. Mouse is switched off on the model and the
  -- overlays so hovering and clicking reach the card underneath.
  card.model = CreateFrame("PlayerModel", nil, card)
  card.model:SetSize(CARD_W - 10, 84)
  card.model:SetPoint("TOP", 0, -4)
  card.model:EnableMouse(false)

  -- Grey overlay, sits above the model while the creature is not killed
  card.shade = CreateFrame("Frame", nil, card)
  card.shade:SetAllPoints(card.model)
  card.shade:SetFrameLevel(card.model:GetFrameLevel() + 3)
  card.shade:EnableMouse(false)
  local tex = card.shade:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetColorTexture(0, 0, 0, 0.72)

  -- Top overlay frame: holds the corner tags. Separate frame above the model
  -- for the same reason as the grey overlay (a model draws over its parent).
  card.top = CreateFrame("Frame", nil, card)
  card.top:SetAllPoints(card.model)
  card.top:SetFrameLevel(card.model:GetFrameLevel() + 5)
  card.top:EnableMouse(false)
  card.tag = card.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  card.tag:SetPoint("TOPLEFT", 3, -3)       -- class (Elite, Critter, ...)
  card.tag2 = card.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  card.tag2:SetPoint("TOPRIGHT", -3, -3)    -- "Unseen"
  card.tag2:SetTextColor(0.7, 0.7, 0.7)

  -- Left-click opens the detail page, right-click opens the class menu
  card:SetScript("OnMouseUp", function(self, button)
    if not self.entry then return end
    if button == "RightButton" then
      ShowClassMenu(self)
    elseif button == "LeftButton" then
      ns.huntDetailEntry = self.entry   -- remember which creature to show
      ns.Refresh()
    end
  end)

  -- Name under the model
  card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  card.name:SetPoint("TOP", card.model, "BOTTOM", 0, -3)
  card.name:SetWidth(CARD_W - 8)
  card.name:SetWordWrap(false)

  -- Faction badges, bottom-left: an "A" and an "H". Each is shown only when
  -- we know how that faction is treated, yellow = neutral, red = hostile.
  card.badges = {}
  for i, letter in ipairs({ "A", "H" }) do
    local fs = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 14, 5)
    fs:SetText(letter)
    fs:Hide()
    card.badges[letter] = fs
  end

  -- Three star slots at the bottom, 20px apart, centered
  card.stars = {}
  for s = 1, 3 do
    local t = card:CreateTexture(nil, "OVERLAY")
    t:SetSize(16, 16)
    t:SetPoint("BOTTOM", (s - 2) * 20, 5)   -- s=1 left, s=2 middle, s=3 right
    t:SetTexture(STAR_TEXTURE)
    card.stars[s] = t
  end

  -- Hover tooltip: name, class, ID, faction treatment, zones, kills, next star
  card:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name)
    GameTooltip:AddLine("ID " .. e.id, 0.7, 0.7, 0.7)
    if e.class ~= "normal" then
      local c = CLASS_COLORS[e.class] or { 1, 1, 1 }
      GameTooltip:AddLine(ns.CLASS_LABELS[e.class], c[1], c[2], c[3])
    end
    if not e.seen then
      GameTooltip:AddLine("Not met yet (starter list)", 0.7, 0.7, 0.7)
    end
    for _, letter in ipairs({ "A", "H" }) do
      local state = e.host and e.host[letter]
      if state then
        local c = HOST_COLOR[state]
        GameTooltip:AddLine(FACTION_NAME[letter] .. ": " .. state, c[1], c[2], c[3])
      end
    end
    if e.where then
      GameTooltip:AddLine(e.where, 0.6, 0.6, 0.6, true)   -- true = wrap long text
    end
    if e.kills > 0 then
      GameTooltip:AddLine("Kills: " .. e.kills, 1, 1, 1)
    else
      GameTooltip:AddLine("Not killed yet", 1, 0.3, 0.3)
    end
    local nxt = NextStarText(e.kills, e.class, e.seen)
    if nxt then
      GameTooltip:AddLine(nxt, 0.6, 0.8, 1)
    else
      GameTooltip:AddLine("All stars earned", 0, 1, 0)
    end
    GameTooltip:AddLine("Click: details   Right-click: set class", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  card:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return card
end

-- Builds the Hunting Log panel inside the main window. Called once from
-- UI.lua. Stores on ui:
--   ui.huntPanel    container for the whole page
--   ui.huntList     the list view (top bar + grid)
--   ui.huntDetail   the detail view
-- plus the controls and text fields used by RefreshHunt (named below).
function ns.CreateHuntPanel(ui)
  local p = CreateFrame("Frame", nil, ui)
  p:SetPoint("TOPLEFT", 156, -32)
  p:SetPoint("BOTTOMRIGHT", -12, 12)
  ui.huntPanel = p
  p:Hide()   -- UI.lua's Refresh decides when it shows
  p:SetScript("OnHide", CloseMenus)   -- don't leave menus floating when you leave the page

  -- =================== LIST VIEW ===================
  local list = CreateFrame("Frame", nil, p)
  list:SetAllPoints()
  ui.huntList = list

  -- ---- Top bar, left side: zone, type, show, summary ----
  -- Zone drop-down
  ui.huntZoneBtn = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  ui.huntZoneBtn:SetSize(180, 22)
  ui.huntZoneBtn:SetPoint("TOPLEFT", 4, -2)
  ui.huntZoneBtn:SetScript("OnClick", function(self)
    if zoneMenu and zoneMenu:IsShown() then
      zoneMenu:Hide()   -- clicking again closes it
    else
      CloseMenus()
      ShowZoneMenu(self)
    end
  end)

  -- Type drop-down (Creatures / Critters / All types)
  ui.huntViewBtn = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  ui.huntViewBtn:SetSize(90, 22)
  ui.huntViewBtn:SetPoint("TOPLEFT", 188, -2)
  ui.huntViewBtn:SetScript("OnClick", function(self)
    ShowChoiceMenu(self, VIEW_CHOICES, ns.Settings().huntView, function(key)
      ns.Settings().huntView = key   -- saved with your settings
      ns.huntPage = 1
      ns.Refresh()
    end)
  end)

  -- Show drop-down (All / Seen / Unseen)
  ui.huntSeenBtn = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  ui.huntSeenBtn:SetSize(100, 22)
  ui.huntSeenBtn:SetPoint("TOPLEFT", 282, -2)
  ui.huntSeenBtn:SetScript("OnClick", function(self)
    ShowChoiceMenu(self, SEEN_CHOICES, ns.Settings().huntSeen, function(key)
      ns.Settings().huntSeen = key
      ns.huntPage = 1
      ns.Refresh()
    end)
  end)

  ui.huntSummary = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.huntSummary:SetPoint("TOPLEFT", 388, -8)

  -- ---- Top bar, right side: paging controls ----
  ui.huntNext = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  ui.huntNext:SetSize(60, 22)
  ui.huntNext:SetPoint("TOPRIGHT", -4, -2)
  ui.huntNext:SetText("Next")
  ui.huntNext:SetScript("OnClick", function()
    ns.huntPage = ns.huntPage + 1   -- RefreshHunt clamps it to the last page
    ns.Refresh()
  end)

  ui.huntPageText = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.huntPageText:SetPoint("RIGHT", ui.huntNext, "LEFT", -10, 0)

  ui.huntPrev = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  ui.huntPrev:SetSize(60, 22)
  ui.huntPrev:SetPoint("RIGHT", ui.huntPageText, "LEFT", -10, 0)
  ui.huntPrev:SetText("Prev")
  ui.huntPrev:SetScript("OnClick", function()
    ns.huntPage = ns.huntPage - 1   -- RefreshHunt clamps it to page 1
    ns.Refresh()
  end)

  -- ---- Grid area below the top bar ----
  local grid = CreateFrame("Frame", nil, list)
  grid:SetPoint("TOPLEFT", 0, -30)
  grid:SetPoint("BOTTOMRIGHT", 0, 0)
  for i = 1, PER_PAGE do
    cards[i] = CreateCard(grid, i)
  end

  -- Message shown in the middle of the grid when the list is empty
  ui.huntEmpty = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.huntEmpty:SetPoint("CENTER", 0, 0)
  ui.huntEmpty:SetText("Nothing here yet.\nTarget or mouse over creatures, or pick a different zone or filter.")
  ui.huntEmpty:Hide()

  -- =================== DETAIL VIEW ===================
  local d = CreateFrame("Frame", nil, p)
  d:SetAllPoints()
  d:Hide()
  ui.huntDetail = d

  -- Back button and creature name across the top
  local back = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  back:SetSize(80, 22)
  back:SetPoint("TOPLEFT", 4, -2)
  back:SetText("< Back")
  back:SetScript("OnClick", function()
    ns.huntDetailEntry = nil   -- back to the list view
    ns.Refresh()
  end)

  ui.huntDetailTitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.huntDetailTitle:SetPoint("LEFT", back, "RIGHT", 12, 0)

  -- Big 3D model, with a dark backing behind it
  local mbg = d:CreateTexture(nil, "BACKGROUND")
  mbg:SetPoint("TOPLEFT", 2, -30)
  mbg:SetSize(184, 184)
  mbg:SetColorTexture(0, 0, 0, 0.35)

  ui.huntDetailModel = CreateFrame("PlayerModel", nil, d)
  ui.huntDetailModel:SetSize(180, 180)
  ui.huntDetailModel:SetPoint("TOPLEFT", 4, -32)
  ui.huntDetailModel:EnableMouse(false)

  -- Three stars under the model
  ui.huntDetailStars = {}
  for s = 1, 3 do
    local t = d:CreateTexture(nil, "OVERLAY")
    t:SetSize(20, 20)
    t:SetPoint("TOP", ui.huntDetailModel, "BOTTOM", (s - 2) * 26, -4)
    t:SetTexture(STAR_TEXTURE)
    ui.huntDetailStars[s] = t
  end

  -- Info text to the right of the model (ID, class, faction, zones, kills,
  -- next star). A creature description will be added in this area later.
  ui.huntDetailInfo = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.huntDetailInfo:SetPoint("TOPLEFT", 204, -36)
  ui.huntDetailInfo:SetWidth(470)
  ui.huntDetailInfo:SetJustifyH("LEFT")
  ui.huntDetailInfo:SetJustifyV("TOP")
  ui.huntDetailInfo:SetSpacing(4)

  -- Loot section under the model
  local lootTitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lootTitle:SetPoint("TOPLEFT", 4, -244)
  lootTitle:SetText("Loot")

  -- Column headings. x positions must line up with the row columns in
  -- GetDetailRow (22, 298, 364, 420).
  local function col(txt, x, w)
    local f = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", 4 + x, -262)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetText(txt)
  end
  col("Item", 22, 270)
  col("ID", 298, 60)
  col("Qty", 364, 50)
  col("Drop rate", 420, 200)

  -- Scrolling loot list
  local ls = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
  ls:SetPoint("TOPLEFT", 4, -278)
  ls:SetPoint("BOTTOMRIGHT", -24, 0)
  local lc = CreateFrame("Frame", nil, ls)
  lc:SetSize(640, 10)
  ls:SetScrollChild(lc)
  ui.huntLootContent = lc

  -- Message shown when no loot has been recorded for this creature
  ui.huntLootEmpty = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.huntLootEmpty:SetPoint("TOPLEFT", 8, -284)
  ui.huntLootEmpty:SetText("No loot recorded yet. Kill and loot this creature to start logging its drops.")
  ui.huntLootEmpty:Hide()
end
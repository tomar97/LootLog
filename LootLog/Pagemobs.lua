--[[
=====================================================================
 PageMobs.lua - the Mob Drops page
=====================================================================
 Two ways to view the same data, switched by the "Expanded" button:
   Two-pane view : mob list on the left, selected mob's drops on the right
   Expanded view : one scrolling list of every mob with all its drops

 Sort options (buttons at the top): Name, Kills, Zone.
 The choices live in LootLogDB.settings (see ns.Settings in Core.lua),
 so they survive /reload.

 Exposes two functions on ns for UI.lua to call:
   ns.CreateMobPanel(ui)  builds the frames, called once when the
                          window is first created
   ns.RefreshMobs(db)     fills them with current data, called on
                          every redraw

 NOTE: the window (ns.ui) does not exist when this file loads, so
 functions below read ns.ui when they RUN, not at the top of the file.
=====================================================================
]]

local ADDON, ns = ...

-- The question asked before deleting a creature's data (right-click it in the
-- list). %s is replaced with the creature's name.
StaticPopupDialogs["LOOTLOG_DELETE_MOB"] = {
  text = "Delete the LootLog data for %s on THIS character?\n\nThis removes its kills (and Hunting Log stars), drops and coin. Other characters keep theirs. It cannot be undone.",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function(self, data)
    local npcID = data or self.data
    if npcID then ns.DeleteMob(npcID) end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local mobRows, dropRows = {}, {}   -- pools of reusable row frames

-- Sort buttons shown at the top of the page. To add a sort:
--   1. add an entry here
--   2. add its comparison to SortedMobs below
local SORTS = {
  { key = "name",  label = "Name" },
  { key = "kills", label = "Kills" },
  { key = "zone",  label = "Zone" },
  { key = "recent", label = "Recent" },   -- the creature you killed most recently first
}


-- =====================================================================
-- DATA HELPERS (no frames are touched here)
-- =====================================================================

-- Returns every mob as a sorted list of { id, m, name, zone }.
--   id   = npcID          m = the mob's data table
--   name = display name ("~" if unknown, so unnamed mobs sort last)
--   zone = the zone this mob is mostly killed in (ns.PrimaryZone)
-- sortKey is "name", "kills", or "zone". Ties fall through to name,
-- then to npcID, so the order is always stable between redraws.
local function SortedMobs(db, sortKey)
  local list = {}
  for npcID, m in pairs(db.mobs) do
    list[#list + 1] = { id = npcID, m = m, name = m.name or "~", zone = ns.PrimaryZone(m) }
  end
  table.sort(list, function(a, b)
    if sortKey == "kills" then
      if a.m.kills ~= b.m.kills then return a.m.kills > b.m.kills end   -- most kills first
    elseif sortKey == "zone" then
      if a.zone ~= b.zone then return a.zone < b.zone end
    elseif sortKey == "recent" then
      -- latest kill first; creatures with no recorded kill time go last
      local ta, tb = a.m.lastKill or 0, b.m.lastKill or 0
      if ta ~= tb then return ta > tb end
    end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return list
end

-- Keeps only the mobs that match the search text (already lower case): the
-- mob's name, its ID, its zone, or the name of any item it dropped. When a
-- rarity is chosen, also keeps only mobs that dropped an item of that rarity.
-- No search and rarity "all" keeps everything.
local function FilterMobs(db, mobs, text, rarity)
  if text == "" and rarity == "all" then return mobs end
  local out = {}
  for _, e in ipairs(mobs) do
    local hit = true
    if text ~= "" then
      hit = (e.m.name or ""):lower():find(text, 1, true)
            or tostring(e.id) == text
            or e.zone:lower():find(text, 1, true)
      if not hit then
        for itemID in pairs(e.m.items) do
          local link = db.items and db.items[itemID]
          local itemName = link and link:match("%[(.-)%]")   -- the name between the brackets of the link
          if itemName and itemName:lower():find(text, 1, true) then hit = true; break end
        end
      end
    end
    if hit and rarity ~= "all" then
      hit = false
      for itemID in pairs(e.m.items) do
        if ns.RarityMatches(rarity, ns.ItemQuality(db, itemID)) then hit = true; break end
      end
    end
    if hit then out[#out + 1] = e end
  end
  return out
end

-- What to say when the list is empty.
local function EmptyMessage()
  local filtered = (ns.mobSearch or "") ~= "" or ns.Settings().rarity ~= "all"
  return filtered and "No creatures match your search or filter." or "No mob drops recorded yet."
end

-- Returns one mob's drops as a list of { id, it, name }, in the order chosen
-- by clicking the table headings (s.dropSort / s.dropDesc), and only the
-- items that fit the rarity filter (s.rarity).
local function SortedDrops(db, m)
  local s = ns.Settings()
  local key, desc = s.dropSort, s.dropDesc
  local drops = {}
  for itemID, it in pairs(m.items) do
    if ns.RarityMatches(s.rarity, ns.ItemQuality(db, itemID)) then
      local link = db.items and db.items[itemID]
      local name = ((link and link:match("%[(.-)%]")) or ""):lower()   -- item name, for sorting by name
      drops[#drops + 1] = { id = itemID, it = it, name = name }
    end
  end
  -- The value each heading sorts by. "rate" is drops / kills, which orders
  -- the same as the number of drops because kills are the same for every item.
  local function value(d)
    if key == "name" then return d.name end
    if key == "id" then return d.id end
    if key == "qty" then return d.it.qty end
    return d.it.drops
  end
  table.sort(drops, function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then
      if desc then return va > vb end
      return va < vb
    end
    if a.it.drops ~= b.it.drops then return a.it.drops > b.it.drops end   -- ties: most common first
    return a.id < b.id
  end)
  return drops
end

-- Text for the "Zones:" line: the top two zones with kill counts, plus
-- "+N more" if there are others. Falls back to the single stored zone for
-- mobs recorded before per-zone tracking existed.
local function ZoneText(m)
  if not m.zones or not next(m.zones) then return m.zone or "Unknown" end
  local zl = {}
  for z, k in pairs(m.zones) do zl[#zl + 1] = { z = z, k = k } end
  table.sort(zl, function(a, b)
    if a.k ~= b.k then return a.k > b.k end
    return a.z < b.z
  end)
  local parts = {}
  for i = 1, math.min(#zl, 2) do
    parts[#parts + 1] = string.format("%s (%d)", zl[i].z, zl[i].k)
  end
  local text = table.concat(parts, ", ")
  if #zl > 2 then text = text .. string.format(", +%d more", #zl - 2) end
  return text
end


-- =====================================================================
-- ROW FRAMES (two-pane view)
-- =====================================================================
-- Row frames are created once and reused. Creating new frames on every
-- refresh would leak memory, because the game never frees frames.

-- One row in the left-hand mob list. i = row number (1 = top).
-- A row is either a clickable mob or (in Zone sort) a zone heading.
local function GetMobRow(i)
  local b = mobRows[i]
  if b then return b end            -- already created, reuse it
  b = CreateFrame("Button", nil, ns.ui.mobContent)
  b:SetSize(160, 20)
  b:SetPoint("TOPLEFT", 0, -(i - 1) * 20)   -- stack rows 20px apart
  b.sel = b:CreateTexture(nil, "BACKGROUND")      -- "selected" highlight
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(1, 1, 1, 0.18)
  b.sel:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")        -- mouse-over highlight
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", 4, 0)
  b.text:SetWidth(154)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if not self.npcID then return end   -- zone headings have no npcID: ignore clicks
    if button == "RightButton" then
      if ns.Settings().allChars then
        -- the combined view is made from several characters, so there is nothing single to delete
        print("LootLog: untick 'All characters' to delete a creature's data for the character you are playing.")
        return
      end
      -- ask first; the question is defined at the top of this file
      StaticPopup_Show("LOOTLOG_DELETE_MOB", self.mobName or tostring(self.npcID), nil, self.npcID)
    else
      ns.selectedMob = self.npcID       -- npcID is set in RefreshMobs
      ns.Refresh()
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.npcID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.mobName or "")
    GameTooltip:AddLine("Right-click to delete this creature's data", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  mobRows[i] = b
  return b
end

-- One row in the right-hand drops table: icon, item, ID, qty, drop rate.
-- Hovering shows the item tooltip.
local function GetDropRow(i)
  local r = dropRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, ns.ui.dropContent)
  r:SetSize(470, 20)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
  r:EnableMouse(true)               -- needed so the row receives hover events
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 0, 0)
  -- Helper that makes one text column at x pixels from the left, w wide.
  -- Column x positions here must match the header positions in
  -- ns.CreateMobPanel below.
  local function fs(x, w)
    local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f:SetPoint("LEFT", x, 0)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
  end
  r.name = fs(22, 190)
  r.id   = fs(216, 55)
  r.qty  = fs(276, 40)
  r.rate = fs(320, 140)
  r:SetScript("OnEnter", function(self)
    if self.link or self.tipLines then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.link then
        GameTooltip:SetHyperlink(self.link)   -- an item row: the item tooltip
      else
        -- the coin row: the lines built by ns.CoinTipLines (title first)
        for i, line in ipairs(self.tipLines) do
          if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1) end
        end
      end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  dropRows[i] = r
  return r
end


-- =====================================================================
-- REFRESH (fills the frames with current data)
-- =====================================================================

-- Expanded view: every mob and all its drops as one block of text.
-- Limitation: plain text, so no item tooltips on hover in this view.
local function RenderExpanded(db, mobs, sortKey)
  local ui = ns.ui
  local lines = {}
  local s = ns.Settings()
  if #mobs == 0 then
    lines[1] = EmptyMessage()
  end
  local lastZone
  for _, e in ipairs(mobs) do
    local m = e.m
    -- In Zone sort, print a green heading whenever the zone changes
    if sortKey == "zone" and e.zone ~= lastZone then
      lines[#lines + 1] = "|cff00ff00== " .. e.zone .. " ==|r"
      lastZone = e.zone
    end
    local kills = math.max(m.kills, 1)   -- avoid dividing by zero
    local lastText = m.lastKill and (" - last kill " .. ns.DateTimeText(m.lastKill)) or ""
    lines[#lines + 1] = string.format("|cffffd100%s|r (ID %d) - kills: %d%s - %s",
      m.name or "Unknown", e.id, m.kills, lastText, ZoneText(m))
    -- Coin line (with the gold coin picture) before the items
    if m.gold and m.gold > 0 and s.rarity == "all" then   -- coin has no rarity, so it is hidden when filtering
      local cd = m.goldDrops or 0
      local rate = ns.RateText(cd, m.kills)
      lines[#lines + 1] = string.format("    |T%s:14|t Coin  %s   %s",
        ns.COIN_ICON, ns.FormatMoney(m.gold), rate)
    end
    for _, d in ipairs(SortedDrops(db, m)) do
      local rate = ns.RateText(d.it.drops, m.kills)
      lines[#lines + 1] = string.format("    %s [ID %d] x%d   %s",
        ns.ItemText(db, d.id), d.id, d.it.qty, rate)
    end
    lines[#lines + 1] = " "   -- blank spacer line between mobs
  end
  ui.expText:SetText(table.concat(lines, "\n"))
  ui.expContent:SetHeight(ui.expText:GetStringHeight() + 10)   -- lets the scrollbar work
end

-- Fills in the Mob Drops page. Called by ns.Refresh in UI.lua.
function ns.RefreshMobs(db)
  local ui = ns.ui
  local s = ns.Settings()   -- saved choices: s.sort and s.expanded

  -- Summary next to the Expanded button: totals over every creature
  local tKills, tMobs = 0, 0
  for _, m in pairs(db.mobs) do
    tMobs = tMobs + 1
    tKills = tKills + m.kills
  end
  ui.mobSummary:SetText(string.format("%d kills, %d creatures", tKills, tMobs))

  -- Update the controls: pressed look on the active sort button,
  -- and the label on the expand toggle.
  for key, b in pairs(ui.sortButtons) do
    if key == s.sort then b:LockHighlight() else b:UnlockHighlight() end
  end
  ui.expandButton:SetText(s.expanded and "Expanded: On" or "Expanded: Off")

  -- Rarity button text, and the arrows on the drops table headings
  local rarityShort = "All"
  for _, c in ipairs(ns.RARITY_CHOICES) do
    if c.key == s.rarity then rarityShort = c.short or c.label end
  end
  ui.rarityButton:SetText("Rarity: " .. rarityShort)
  for key, hb in pairs(ui.dropHeads) do
    if key == s.dropSort then
      hb.text:SetText(hb.label .. (s.dropDesc and " v" or " ^"))   -- v = biggest first, ^ = smallest first
      hb.text:SetTextColor(1, 0.82, 0)
    else
      hb.text:SetText(hb.label)
      hb.text:SetTextColor(0.75, 0.75, 0.75)
    end
  end

  -- Show either the two-pane view or the expanded view, never both
  ui.split:SetShown(not s.expanded)
  ui.exp:SetShown(s.expanded)

  local mobs = FilterMobs(db, SortedMobs(db, s.sort), ns.mobSearch or "", s.rarity)

  if s.expanded then
    RenderExpanded(db, mobs, s.sort)
    return
  end

  -- ---- Two-pane view ----

  -- Select the first mob if nothing is selected or it is not in the list
  -- (it may have been filtered out by the search)
  local inList = {}
  for _, e in ipairs(mobs) do inList[e.id] = true end
  if not ns.selectedMob or not inList[ns.selectedMob] then
    ns.selectedMob = mobs[1] and mobs[1].id or nil
  end

  -- Left list entries: the mobs, plus a zone heading before each new
  -- zone when sorting by Zone. A heading entry looks like { header = "Zone" }.
  local entries = {}
  local lastZone
  for _, e in ipairs(mobs) do
    if s.sort == "zone" and e.zone ~= lastZone then
      entries[#entries + 1] = { header = e.zone }
      lastZone = e.zone
    end
    entries[#entries + 1] = e
  end

  -- Fill one row per entry, hide any leftover rows from earlier refreshes
  for i, e in ipairs(entries) do
    local b = GetMobRow(i)
    if e.header then
      b.npcID = nil                                   -- not clickable
      b.mobName = nil
      b.text:SetText("|cff00ff00" .. e.header .. "|r")
      b.sel:Hide()
    else
      b.npcID = e.id
      b.mobName = e.m.name or ("ID " .. e.id)         -- shown in the delete question
      b.text:SetText(string.format("%s (%d)", e.m.name or ("ID " .. e.id), e.m.kills))
      b.sel:SetShown(e.id == ns.selectedMob)
    end
    b:Show()
  end
  for i = #entries + 1, #mobRows do mobRows[i]:Hide() end
  ui.mobContent:SetHeight(math.max(#entries * 20, 1))   -- lets the scrollbar work

  -- Right side: header and drops for the selected mob
  local m = ns.selectedMob and db.mobs[ns.selectedMob]
  if not m then
    ui.mobHeader:SetText(EmptyMessage())
    for i = 1, #dropRows do dropRows[i]:Hide() end
    return
  end
  -- Line 2: kills and zones. Line 3: your first and latest kill, with date and
  -- time (only for kills recorded since dates were added).
  local line2 = "Kills: " .. m.kills .. "     Zones: " .. ZoneText(m)
  local line3 = ""
  if m.firstKill then
    line3 = "\nFirst: " .. ns.DateTimeText(m.firstKill) ..
            "     Last: " .. ns.DateTimeText(m.lastKill or m.firstKill)
  end
  ui.mobHeader:SetText(string.format("|cffffd100%s|r  (ID %d)\n%s%s",
    m.name or "Unknown", ns.selectedMob, line2, line3))

  local drops = SortedDrops(db, m)
  local kills = math.max(m.kills, 1)   -- avoid dividing by zero

  -- Row 1 is the coin row (gold coin picture) when this creature has dropped
  -- any coin. The items follow it, so they start `first` rows further down.
  local hasCoin = m.gold and m.gold > 0 and s.rarity == "all"   -- coin has no rarity
  local first = hasCoin and 1 or 0
  if hasCoin then
    local r = GetDropRow(1)
    local coinDrops = m.goldDrops or 0
    r.link = nil
    r.tipLines = ns.CoinTipLines(m, m.kills)   -- hover text for the coin row
    r.icon:SetTexture(ns.COIN_ICON)
    r.name:SetText("Coin  " .. ns.FormatMoney(m.gold))
    r.id:SetText("-")
    r.qty:SetText("")
    r.rate:SetText(ns.RateText(coinDrops, m.kills))
    r:Show()
  end

  for i, d in ipairs(drops) do
    local r = GetDropRow(i + first)
    local link = db.items and db.items[d.id]
    r.link = link                       -- used by the hover tooltip
    r.tipLines = nil                    -- (only the coin row uses this)
    r.icon:SetTexture(ns.GetIcon(db, d.id))
    r.name:SetText(link or ("item:" .. d.id))
    r.id:SetText(d.id)
    r.qty:SetText("x" .. d.it.qty)
    -- Drop rate: times it dropped / total kills
    r.rate:SetText(ns.RateText(d.it.drops, m.kills))
    r:Show()
  end
  for i = #drops + first + 1, #dropRows do dropRows[i]:Hide() end
  ui.dropContent:SetHeight(math.max((#drops + first) * 20, 1))
end


-- =====================================================================
-- FRAME CONSTRUCTION
-- =====================================================================

-- Builds the Mob Drops frames inside the main window.
-- Called once from UI.lua. Stores the frames it creates on ui so
-- RefreshMobs can find them:
--   ui.mobPanel      container for the whole page
--   ui.sortButtons   { name=button, kills=button, zone=button }
--   ui.expandButton  the Expanded on/off toggle
--   ui.split         container for the two-pane view
--   ui.mobContent    scroll child holding the mob list rows
--   ui.mobHeader     text: mob name, kills, zones
--   ui.dropContent   scroll child holding the drops table rows
--   ui.exp           container for the expanded view
--   ui.expContent / ui.expText   scroll child and text of the expanded view
function ns.CreateMobPanel(ui)
  -- Container for the whole page
  local p = CreateFrame("Frame", nil, ui)
  p:SetPoint("TOPLEFT", 156, -32)
  p:SetPoint("BOTTOMRIGHT", -12, 12)
  ui.mobPanel = p

  -- ---- Controls bar (top 28px): "Sort by:" label, 3 buttons, toggle ----
  local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 4, -6)
  label:SetText("Sort by:")

  ui.sortButtons = {}
  local x = 60   -- running x position for the next button
  for _, sort in ipairs(SORTS) do
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(64, 22)
    b:SetPoint("TOPLEFT", x, -2)
    b:SetText(sort.label)
    b:SetScript("OnClick", function()
      ns.Settings().sort = sort.key   -- saved with the rest of the data
      ns.Refresh()
    end)
    ui.sortButtons[sort.key] = b
    x = x + 68
  end

  local eb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  eb:SetSize(110, 22)
  eb:SetPoint("TOPLEFT", x + 20, -2)
  eb:SetScript("OnClick", function()
    local st = ns.Settings()
    st.expanded = not st.expanded
    ns.Refresh()
  end)
  ui.expandButton = eb

  -- Rarity filter drop-down: show only drops of one item quality (and only
  -- the creatures that have such drops). Choices are ns.RARITY_CHOICES.
  local rb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  rb:SetSize(100, 22)
  rb:SetPoint("LEFT", eb, "RIGHT", 6, 0)
  rb:SetScript("OnClick", function(self)
    if not ns.ShowChoiceMenu then return end   -- the drop-down helper lives in PageHunt.lua
    ns.ShowChoiceMenu(self, ns.RARITY_CHOICES, ns.Settings().rarity, function(key)
      ns.Settings().rarity = key               -- saved with your settings
      ns.Refresh()
    end)
  end)
  ui.rarityButton = rb

  -- Search box: type part of a creature name, item name, zone, or a creature
  -- ID to filter the list (both the two-pane and the Expanded view).
  local sb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  sb:SetSize(120, 20)
  sb:SetPoint("LEFT", rb, "RIGHT", 8, 0)
  sb:SetAutoFocus(false)            -- don't grab the keyboard when the window opens
  sb:SetMaxLetters(30)
  local hint = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- grey "Search..." while empty
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search...")
  hint:SetTextColor(0.5, 0.5, 0.5)
  sb:SetScript("OnTextChanged", function(self)
    local text = self:GetText():lower()
    hint:SetShown(text == "")
    if text ~= (ns.mobSearch or "") then
      ns.mobSearch = text           -- session only, not saved
      ns.Refresh()
    end
  end)
  sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  ui.mobSearchBox = sb



  -- ---- Two-pane view container (everything below the controls bar) ----
  local split = CreateFrame("Frame", nil, p)
  split:SetPoint("TOPLEFT", 0, -30)
  split:SetPoint("BOTTOMRIGHT", 0, 0)
  ui.split = split

  -- Left: scrolling list of mobs
  local ms = CreateFrame("ScrollFrame", nil, split, "UIPanelScrollFrameTemplate")
  ms:SetPoint("TOPLEFT", 0, 0)
  ms:SetPoint("BOTTOMLEFT", 0, 18)   -- leaves a line underneath for the totals
  ms:SetWidth(170)
  local mc = CreateFrame("Frame", nil, ms)
  mc:SetSize(165, 10)
  ms:SetScrollChild(mc)
  ui.mobContent = mc

  -- Totals under the mob list (filled in by RefreshMobs)
  ui.mobSummary = split:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ui.mobSummary:SetPoint("BOTTOMLEFT", split, "BOTTOMLEFT", 4, 2)
  ui.mobSummary:SetTextColor(0.7, 0.7, 0.7)

  -- Right: header text (3 lines: name, kills, zones)
  ui.mobHeader = split:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.mobHeader:SetPoint("TOPLEFT", 205, 0)
  ui.mobHeader:SetWidth(470)
  ui.mobHeader:SetJustifyH("LEFT")

  -- Right: column headings. x positions must line up with the row
  -- columns defined in GetDropRow (22, 216, 276, 320).
  -- Each heading is a button: click it to sort the table by that column,
  -- click it again to reverse. RefreshMobs adds the arrow to the active one.
  ui.dropHeads = {}
  local function col(key, txt, cx, w)
    local hb = CreateFrame("Button", nil, split)
    hb:SetPoint("TOPLEFT", 205 + cx, -56)
    hb:SetSize(w, 16)
    hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hb.text:SetPoint("LEFT", 0, 0)
    hb.text:SetJustifyH("LEFT")
    hb.label = txt
    local hl = hb:CreateTexture(nil, "HIGHLIGHT")   -- mouse-over highlight
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    hb:SetScript("OnClick", function()
      local st = ns.Settings()
      if st.dropSort == key then
        st.dropDesc = not st.dropDesc                      -- same heading again: reverse
      else
        st.dropSort = key
        st.dropDesc = (key == "qty" or key == "rate")      -- numbers start biggest first, names A to Z
      end
      ns.Refresh()
    end)
    ui.dropHeads[key] = hb
  end
  col("name", "Item", 22, 190)
  col("id", "ID", 216, 55)
  col("qty", "Qty", 276, 40)
  col("rate", "Drop rate", 320, 140)

  -- Right: scrolling table of the selected mob's drops
  local ds = CreateFrame("ScrollFrame", nil, split, "UIPanelScrollFrameTemplate")
  ds:SetPoint("TOPLEFT", 205, -74)
  ds:SetPoint("BOTTOMRIGHT", -24, 0)
  local dc = CreateFrame("Frame", nil, ds)
  dc:SetSize(470, 10)
  ds:SetScrollChild(dc)
  ui.dropContent = dc

  -- ---- Expanded view container: one scrolling block of text ----
  local exp = CreateFrame("Frame", nil, p)
  exp:SetPoint("TOPLEFT", 0, -30)
  exp:SetPoint("BOTTOMRIGHT", 0, 0)
  ui.exp = exp

  local es = CreateFrame("ScrollFrame", nil, exp, "UIPanelScrollFrameTemplate")
  es:SetPoint("TOPLEFT", 0, 0)
  es:SetPoint("BOTTOMRIGHT", -24, 0)
  local ec = CreateFrame("Frame", nil, es)
  ec:SetSize(660, 10)
  es:SetScrollChild(ec)
  local et = ec:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  et:SetPoint("TOPLEFT")
  et:SetWidth(660)
  et:SetJustifyH("LEFT")
  ui.expContent, ui.expText = ec, et
  exp:Hide()   -- RefreshMobs decides which view shows
end
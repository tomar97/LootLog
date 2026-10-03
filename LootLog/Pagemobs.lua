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

local mobRows, dropRows = {}, {}   -- pools of reusable row frames

-- Sort buttons shown at the top of the page. To add a sort:
--   1. add an entry here
--   2. add its comparison to SortedMobs below
local SORTS = {
  { key = "name",  label = "Name" },
  { key = "kills", label = "Kills" },
  { key = "zone",  label = "Zone" },
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
    end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return list
end

-- Returns one mob's drops as a list of { id, it }, most common first.
local function SortedDrops(m)
  local drops = {}
  for itemID, it in pairs(m.items) do drops[#drops + 1] = { id = itemID, it = it } end
  table.sort(drops, function(a, b)
    if a.it.drops ~= b.it.drops then return a.it.drops > b.it.drops end
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
  b:SetScript("OnClick", function(self)
    if not self.npcID then return end   -- zone headings have no npcID: ignore clicks
    ns.selectedMob = self.npcID         -- npcID is set in RefreshMobs
    ns.Refresh()
  end)
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
  if #mobs == 0 then lines[1] = "No mob drops recorded yet." end
  local lastZone
  for _, e in ipairs(mobs) do
    local m = e.m
    -- In Zone sort, print a green heading whenever the zone changes
    if sortKey == "zone" and e.zone ~= lastZone then
      lines[#lines + 1] = "|cff00ff00== " .. e.zone .. " ==|r"
      lastZone = e.zone
    end
    local kills = math.max(m.kills, 1)   -- avoid dividing by zero
    lines[#lines + 1] = string.format("|cffffd100%s|r (ID %d) - kills: %d - %s",
      m.name or "Unknown", e.id, m.kills, ZoneText(m))
    -- Coin line (with the gold coin picture) before the items
    if m.gold and m.gold > 0 then
      local cd = m.goldDrops or 0
      lines[#lines + 1] = string.format("    |T%s:14|t Coin  %s   %d/%d (%.1f%%)",
        ns.COIN_ICON, ns.FormatMoney(m.gold), cd, kills, 100 * cd / kills)
    end
    for _, d in ipairs(SortedDrops(m)) do
      lines[#lines + 1] = string.format("    %s [ID %d] x%d   %d/%d (%.1f%%)",
        ns.ItemText(db, d.id), d.id, d.it.qty, d.it.drops, kills, 100 * d.it.drops / kills)
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

  -- Update the controls: pressed look on the active sort button,
  -- and the label on the expand toggle.
  for key, b in pairs(ui.sortButtons) do
    if key == s.sort then b:LockHighlight() else b:UnlockHighlight() end
  end
  ui.expandButton:SetText(s.expanded and "Expanded: On" or "Expanded: Off")

  -- Show either the two-pane view or the expanded view, never both
  ui.split:SetShown(not s.expanded)
  ui.exp:SetShown(s.expanded)

  local mobs = SortedMobs(db, s.sort)

  if s.expanded then
    RenderExpanded(db, mobs, s.sort)
    return
  end

  -- ---- Two-pane view ----

  -- Select the first mob if nothing is selected or it no longer exists
  if not ns.selectedMob or not db.mobs[ns.selectedMob] then
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
      b.text:SetText("|cff00ff00" .. e.header .. "|r")
      b.sel:Hide()
    else
      b.npcID = e.id
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
    ui.mobHeader:SetText("No mob drops recorded yet.")
    for i = 1, #dropRows do dropRows[i]:Hide() end
    return
  end
  ui.mobHeader:SetText(string.format("|cffffd100%s|r  (ID %d)\nKills: %d\nZones: %s",
    m.name or "Unknown", ns.selectedMob, m.kills, ZoneText(m)))

  local drops = SortedDrops(m)
  local kills = math.max(m.kills, 1)   -- avoid dividing by zero

  -- Row 1 is the coin row (gold coin picture) when this creature has dropped
  -- any coin. The items follow it, so they start `first` rows further down.
  local hasCoin = m.gold and m.gold > 0
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
    r.rate:SetText(string.format("%d/%d (%.1f%%)", coinDrops, kills, 100 * coinDrops / kills))
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
    r.rate:SetText(string.format("%d/%d (%.1f%%)", d.it.drops, kills, 100 * d.it.drops / kills))
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

  -- ---- Two-pane view container (everything below the controls bar) ----
  local split = CreateFrame("Frame", nil, p)
  split:SetPoint("TOPLEFT", 0, -30)
  split:SetPoint("BOTTOMRIGHT", 0, 0)
  ui.split = split

  -- Left: scrolling list of mobs
  local ms = CreateFrame("ScrollFrame", nil, split, "UIPanelScrollFrameTemplate")
  ms:SetPoint("TOPLEFT", 0, 0)
  ms:SetPoint("BOTTOMLEFT", 0, 0)
  ms:SetWidth(170)
  local mc = CreateFrame("Frame", nil, ms)
  mc:SetSize(165, 10)
  ms:SetScrollChild(mc)
  ui.mobContent = mc

  -- Right: header text (3 lines: name, kills, zones)
  ui.mobHeader = split:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.mobHeader:SetPoint("TOPLEFT", 205, 0)
  ui.mobHeader:SetWidth(470)
  ui.mobHeader:SetJustifyH("LEFT")

  -- Right: column headings. x positions must line up with the row
  -- columns defined in GetDropRow (22, 216, 276, 320).
  local function col(txt, cx, w)
    local f = split:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", 205 + cx, -58)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetText(txt)
  end
  col("Item", 22, 190)
  col("ID", 216, 55)
  col("Qty", 276, 40)
  col("Drop rate", 320, 140)

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
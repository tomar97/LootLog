--[[
=====================================================================
 PageFishing.lua - the Fishing Log (a journal of everything you can catch)
=====================================================================
 LAYOUT
   Left   a list of zones: "Current zone", "All zones", then every zone you
          have caught something in, each with a count.
   Right  the selected zone's catches as small icon tiles, grouped into
          sections (Fish, Big fish, Materials, Gear...).

 EACH TILE
   - the item's icon (greyed out until you have caught it)
   - a border in the item's quality color once caught
   - how many you have caught, in the bottom-right corner
   - stars underneath: true fish earn up to 3 (5/25/50 catches), big fish up to
     3 (1/2/5), everything else 1 star for the first catch. The numbers
     are in FishData.lua (ns.FISH_STAR_TIERS). Stars count your catches in
     ALL zones added together.
   - below the stars, its share of your catches in that zone (or overall)
   - hover for the item tooltip plus your catch details

 WHERE THE DATA COMES FROM
   ns.FishList (FishData.lua)   every fishable item, with type and skill
   db.events["Fishing"]         your catches: [zone][itemID] = { count, quality }
                                (written by Capture.lua when you fish something up)
 Zones come only from your catches. "All zones" lists every item in
 FishData.lua, greyed out until caught. A single zone lists what you have
 caught there (and, if FishData.lua ever gains per-zone lists, the items
 expected there too).

 Exposes two functions on ns for UI.lua:
   ns.CreateFishPanel(ui)   builds the frames, called once
   ns.RefreshFish(db)       fills them with current data on every redraw
=====================================================================
]]

local ADDON, ns = ...

-- ===== LAYOUT (pixels) =====
local TILE = 52                 -- the square icon tile
local CELL_W, CELL_H = 62, 92   -- one tile plus its stars, percent label, and spacing
local STAR_SIZE = 11
local STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"   -- built-in yellow star
local PER_ROW = 8               -- tiles per row (8 x 62 = 496 wide)
local ZONE_ROW_H = 20

local CURRENT = "@current"      -- special zone choice: the zone you are standing in

-- Choices for the Show drop-down
local SHOW_CHOICES = {
  { key = "all",       label = "All" },
  { key = "caught",    label = "Caught" },
  { key = "notcaught", label = "Not caught" },
}

local function ShowLabel(key)
  for _, c in ipairs(SHOW_CHOICES) do
    if c.key == key then return c.label end
  end
  return "All"
end

local zoneRows, tiles, headers = {}, {}, {}   -- pools of reusable frames


-- =====================================================================
-- BUILDING WHAT TO SHOW (no frames are touched here)
-- =====================================================================

-- Which section an item belongs to (see the bottom of FishData.lua).
-- row is the item's entry in ns.FishList, or nil for an item not in the list.
local function SectionOf(row, itemID)
  return ns.FishSectionOfRow(row, itemID)   -- shared with the chat messages (Core.lua)
end

-- Returns a table describing everything the page needs:
--   zoneKey   the zone being viewed, or nil for "All zones"
--   sections  { { name, entries }, ... } in display order (after the Show filter)
--   caught    how many items in this view are caught
--   total     how many items are in this view
--   catches   total catches in this view (the 100% for the percentages)
--   zoneRows  rows for the left zone list
-- s is the settings table (ns.Settings()): s.fishZone and s.fishShow.
local function BuildFish(db, s)
  local fishing = (db.events and db.events["Fishing"]) or {}   -- [zone][itemID] = { count, quality, name }
  local list = ns.FishList or {}
  local listed = {}                                            -- itemID -> its FishData row
  for _, row in ipairs(list) do listed[row.id] = row end

  -- Totals: per item (all zones), per zone, and overall
  local itemTotal, itemZones, zoneTotal, zoneKinds, grand = {}, {}, {}, {}, 0
  local quality, evName = {}, {}
  for zone, items in pairs(fishing) do
    local t, kinds = 0, 0
    for itemID, e in pairs(items) do
      t = t + e.count
      kinds = kinds + 1
      itemTotal[itemID] = (itemTotal[itemID] or 0) + e.count
      itemZones[itemID] = itemZones[itemID] or {}
      itemZones[itemID][zone] = e.count
      if e.quality then quality[itemID] = e.quality end
      if e.name then evName[itemID] = e.name end
    end
    zoneTotal[zone], zoneKinds[zone] = t, kinds
    grand = grand + t
  end

  -- Which zone is being viewed
  local currentZone = GetRealZoneText() or ""
  local zoneKey                                    -- nil = all zones
  if s.fishZone == CURRENT then
    zoneKey = currentZone
  elseif s.fishZone ~= "All" and fishing[s.fishZone] then
    zoneKey = s.fishZone
  else
    s.fishZone = "All"                             -- saved zone has no catches any more
  end

  -- Which item IDs belong to this view
  local ids = {}
  if zoneKey then
    for itemID in pairs(fishing[zoneKey] or {}) do ids[itemID] = true end
    for _, row in ipairs(list) do                  -- room for per-zone lists in FishData.lua later
      if row.zones and row.zones[zoneKey] then ids[row.id] = true end
    end
  else
    for _, row in ipairs(list) do ids[row.id] = true end
    for itemID in pairs(itemTotal) do ids[itemID] = true end
  end

  -- One entry per item
  local denom = zoneKey and (zoneTotal[zoneKey] or 0) or grand
  local bySection, caught, total = {}, 0, 0
  for itemID in pairs(ids) do
    local row = listed[itemID]
    local count
    if zoneKey then
      local e = fishing[zoneKey] and fishing[zoneKey][itemID]
      count = e and e.count or 0
    else
      count = itemTotal[itemID] or 0
    end
    total = total + 1
    if count > 0 then caught = caught + 1 end

    local show = (s.fishShow == "all")
                 or (s.fishShow == "caught" and count > 0)
                 or (s.fishShow == "notcaught" and count == 0)
    if show then
      local sec = SectionOf(row, itemID)
      -- Stars come from your catches in ALL zones added together, using the
      -- numbers for this section in FishData.lua (ns.FISH_STAR_TIERS).
      local tiers = (ns.FISH_STAR_TIERS and ns.FISH_STAR_TIERS[sec]) or ns.FISH_STAR_DEFAULT or { 1 }
      local overall = itemTotal[itemID] or 0
      local stars = 0
      for _, tier in ipairs(tiers) do
        if overall >= tier then stars = stars + 1 end
      end
      bySection[sec] = bySection[sec] or {}
      table.insert(bySection[sec], {
        id = itemID,
        name = (row and row.name) or evName[itemID] or ("Item " .. itemID),
        type = row and row.type,
        unlisted = (row == nil),   -- not in FishData.lua; it was sorted into a section automatically
        skill = row and row.skill,
        count = count,
        total = itemTotal[itemID] or 0,
        pct = (denom > 0) and (count / denom * 100) or 0,
        quality = quality[itemID],
        zones = itemZones[itemID],
        tiers = tiers,   -- catches needed for each star
        stars = stars,   -- stars earned so far
      })
    end
  end

  -- Sections in the order set in FishData.lua, then any others
  local order, seenSec = {}, {}
  for _, name in ipairs(ns.FISH_SECTION_ORDER or {}) do
    if bySection[name] then order[#order + 1] = name; seenSec[name] = true end
  end
  for name in pairs(bySection) do
    if not seenSec[name] then order[#order + 1] = name end
  end
  local sections = {}
  for _, name in ipairs(order) do
    local entries = bySection[name]
    -- Caught items first (most caught first), then the rest by skill needed, then name
    table.sort(entries, function(a, b)
      if (a.count > 0) ~= (b.count > 0) then return a.count > 0 end
      if a.count > 0 then
        if a.count ~= b.count then return a.count > b.count end
      else
        local sa, sb = a.skill or 999, b.skill or 999
        if sa ~= sb then return sa < sb end
      end
      if a.name ~= b.name then return a.name < b.name end
      return a.id < b.id
    end)
    sections[#sections + 1] = { name = name, entries = entries }
  end

  -- Rows for the zone list on the left
  local zones = {}
  for z in pairs(fishing) do zones[#zones + 1] = z end
  table.sort(zones)
  local zrows = {
    { key = CURRENT, label = "Current zone", extra = currentZone },
    { key = "All",   label = "All zones", extra = string.format("%d/%d", (function()
        local n = 0
        for id in pairs(itemTotal) do n = n + 1 end
        return n
      end)(), #list) },
  }
  for _, z in ipairs(zones) do
    zrows[#zrows + 1] = { key = z, label = z, extra = tostring(zoneKinds[z]) }
  end

  return {
    zoneKey = zoneKey, sections = sections, caught = caught, total = total,
    catches = denom, zoneRows = zrows,
  }
end


-- =====================================================================
-- ROW AND TILE FRAMES
-- =====================================================================
-- Frames are created once and reused (the game never frees frames).

-- One row of the zone list on the left.
local function GetZoneRow(i)
  local b = zoneRows[i]
  if b then return b end
  b = CreateFrame("Button", nil, ns.ui.fishZoneContent)
  b:SetSize(160, ZONE_ROW_H)
  b:SetPoint("TOPLEFT", 0, -(i - 1) * ZONE_ROW_H)
  b.sel = b:CreateTexture(nil, "BACKGROUND")        -- "selected" highlight
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(1, 1, 1, 0.18)
  b.sel:Hide()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")      -- mouse-over highlight
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("LEFT", 4, 0)
  b.text:SetWidth(100)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b.extra = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.extra:SetPoint("RIGHT", -4, 0)
  b.extra:SetWidth(54)
  b.extra:SetJustifyH("RIGHT")
  b.extra:SetWordWrap(false)
  b:SetScript("OnClick", function(self)
    ns.Settings().fishZone = self.key        -- saved with your settings
    ns.ui.fishScroll:SetVerticalScroll(0)
    ns.Refresh()
  end)
  zoneRows[i] = b
  return b
end

-- A section heading on the right.
local function GetHeader(i)
  local h = headers[i]
  if h then return h end
  h = ns.ui.fishContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetJustifyH("LEFT")
  headers[i] = h
  return h
end

-- One tile: icon, border, count, percent label, tooltip.
local function GetTile(i)
  local t = tiles[i]
  if t then return t end
  t = CreateFrame("Frame", nil, ns.ui.fishContent)
  t:SetSize(CELL_W, CELL_H)
  t:EnableMouse(true)                                 -- so hovering works

  -- The border is a coloured square just behind a slightly smaller icon
  t.border = t:CreateTexture(nil, "BACKGROUND")
  t.border:SetSize(TILE, TILE)
  t.border:SetPoint("TOP", 0, 0)
  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(TILE - 4, TILE - 4)
  t.icon:SetPoint("CENTER", t.border, "CENTER")

  -- Catch count in the bottom-right corner of the tile
  t.count = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t.count:SetPoint("BOTTOMRIGHT", t.border, "BOTTOMRIGHT", -2, 2)
  t.count:SetTextColor(1, 1, 1)

  -- Up to three stars under the tile (positioned in FillTile)
  t.stars = {}
  for s = 1, 3 do
    local star = t:CreateTexture(nil, "OVERLAY")
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetTexture(STAR_TEXTURE)
    t.stars[s] = star
  end

  -- Share of catches under the stars
  t.pct = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t.pct:SetPoint("TOP", t.border, "BOTTOM", 0, -16)
  t.pct:SetTextColor(0.7, 0.7, 0.7)

  -- Hover: the item tooltip, then your catch details
  t:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.id)
    if not ok then GameTooltip:AddLine(e.name) end
    GameTooltip:AddLine(" ")
    if e.total == 0 and e.count == 0 then
      GameTooltip:AddLine("Not caught yet", 1, 0.3, 0.3)
    else
      if self.zoneKey then
        GameTooltip:AddLine("Caught here: " .. e.count, 1, 1, 1)
        GameTooltip:AddLine("Caught in all zones: " .. e.total, 1, 1, 1)
      else
        GameTooltip:AddLine("Caught: " .. e.count, 1, 1, 1)
      end
      if e.count > 0 then
        GameTooltip:AddLine(string.format("%.1f%% of your catches %s", e.pct,
          self.zoneKey and "in this zone" or "overall"), 0.7, 0.7, 0.7)
      end
    end
    -- Stars: what is earned and what is next (counted over all zones)
    local nextTier
    for _, tier in ipairs(e.tiers) do
      if e.total < tier then nextTier = tier; break end
    end
    if #e.tiers == 1 then
      GameTooltip:AddLine(e.stars >= 1 and "Star earned" or "Catch one to earn its star", 0.6, 0.8, 1)
    elseif nextTier then
      GameTooltip:AddLine(string.format("%d of %d stars. Next star at %d catches", e.stars, #e.tiers, nextTier), 0.6, 0.8, 1)
    else
      GameTooltip:AddLine("All stars earned", 0, 1, 0)
    end
    if e.skill then GameTooltip:AddLine("Needs fishing skill " .. e.skill, 0.6, 0.8, 1) end
    if e.unlisted then
      GameTooltip:AddLine("Not in your fishing list file yet. Sorted into this section automatically.", 1, 0.8, 0.4, true)
    end
    if e.type then GameTooltip:AddLine("Type: " .. e.type, 0.6, 0.6, 0.6) end
    if e.zones then
      local names = {}
      for z in pairs(e.zones) do names[#names + 1] = z end
      table.sort(names)
      if #names > 0 then
        local shown = {}
        for k = 1, math.min(#names, 4) do shown[k] = names[k] end
        local text = "Caught in: " .. table.concat(shown, ", ")
        if #names > 4 then text = text .. string.format(" +%d more", #names - 4) end
        GameTooltip:AddLine(text, 0.6, 0.6, 0.6, true)   -- true = wrap long text
      end
    end
    if not e.type then
      GameTooltip:AddLine("Not in your list yet", 1, 0.82, 0)
    end
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)

  tiles[i] = t
  return t
end

-- Fills one tile with one item's data.
local function FillTile(t, e, zoneKey, db)
  t.entry = e
  t.zoneKey = zoneKey
  local caught = e.count > 0

  t.icon:SetTexture(ns.GetIcon(db, e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
  t.icon:SetDesaturated(not caught)
  t.icon:SetAlpha(caught and 1 or 0.4)

  -- Border: the item's quality colour once caught, dark grey before
  if caught then
    local q = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
    if q then t.border:SetColorTexture(q.r, q.g, q.b, 1)
    else t.border:SetColorTexture(0.6, 0.6, 0.6, 1) end
  else
    t.border:SetColorTexture(0.2, 0.2, 0.2, 1)
  end

  t.count:SetText(caught and e.count or "")
  if caught then
    t.pct:SetText(e.pct < 1 and "<1%" or string.format("%.0f%%", e.pct))
  else
    t.pct:SetText("--")
  end

  -- Stars: one slot for items that earn a single star (centered), three
  -- for fish. Earned stars are bright, the rest dim.
  local n = #e.tiers
  for s = 1, 3 do
    local star = t.stars[s]
    if s <= n then
      local x = (n == 1) and 0 or (s - 2) * (STAR_SIZE + 2)
      star:ClearAllPoints()
      star:SetPoint("TOP", t.border, "BOTTOM", x, -2)
      star:Show()
      if s <= e.stars then
        star:SetDesaturated(false)
        star:SetAlpha(1)
      else
        star:SetDesaturated(true)
        star:SetAlpha(0.3)
      end
    else
      star:Hide()
    end
  end
end


-- =====================================================================
-- REFRESH
-- =====================================================================

function ns.RefreshFish(db)
  local ui = ns.ui
  local s = ns.Settings()
  local data = BuildFish(db, s)

  -- ---- Zone list (left) ----
  for i, r in ipairs(data.zoneRows) do
    local b = GetZoneRow(i)
    b.key = r.key
    b.text:SetText(r.label)
    b.extra:SetText(r.extra or "")
    b.sel:SetShown(r.key == s.fishZone)
    b:Show()
  end
  for i = #data.zoneRows + 1, #zoneRows do zoneRows[i]:Hide() end
  ui.fishZoneContent:SetHeight(math.max(#data.zoneRows * ZONE_ROW_H, 1))

  -- ---- Header (right) ----
  local title
  if s.fishZone == CURRENT then
    title = "Current zone: " .. (GetRealZoneText() or "unknown")
  elseif data.zoneKey then
    title = data.zoneKey
  else
    title = "All zones"
  end
  ui.fishTitle:SetText(title)

  if data.zoneKey then
    -- A single zone: we only know what you caught there
    ui.fishCount:SetText(string.format("%d different catches here  (%d caught in all)", data.caught, data.catches))
    ui.fishBarBG:Hide()
    ui.fishBar:Hide()
  else
    -- All zones: every item in FishData.lua, so we can show a real total
    ui.fishCount:SetText(string.format("%d of %d caught", data.caught, data.total))
    local frac = (data.total > 0) and (data.caught / data.total) or 0
    ui.fishBarBG:Show()
    ui.fishBar:SetWidth(math.max(frac * 480, 1))
    ui.fishBar:SetShown(data.caught > 0)
  end
  ui.fishShowBtn:SetText("Show: " .. ShowLabel(s.fishShow))

  -- ---- Sections and tiles (right) ----
  local y, tileIndex = 0, 0
  for sIdx, sec in ipairs(data.sections) do
    local h = GetHeader(sIdx)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", ui.fishContent, "TOPLEFT", 0, -y)
    local got = 0
    for _, e in ipairs(sec.entries) do
      if e.count > 0 then got = got + 1 end
    end
    h:SetText(string.format("%s  |cffaaaaaa%d of %d|r", sec.name, got, #sec.entries))
    h:Show()
    y = y + 22

    for i, e in ipairs(sec.entries) do
      tileIndex = tileIndex + 1
      local t = GetTile(tileIndex)
      local col = (i - 1) % PER_ROW
      local row = math.floor((i - 1) / PER_ROW)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", ui.fishContent, "TOPLEFT", col * CELL_W, -(y + row * CELL_H))
      FillTile(t, e, data.zoneKey, db)
      t:Show()
    end
    y = y + math.ceil(#sec.entries / PER_ROW) * CELL_H + 8
  end
  for i = #data.sections + 1, #headers do headers[i]:Hide() end
  for i = tileIndex + 1, #tiles do tiles[i]:Hide() end
  ui.fishContent:SetHeight(math.max(y, 1))   -- lets the scrollbar work

  -- ---- Message when there is nothing to show ----
  if tileIndex == 0 then
    if data.zoneKey then
      ui.fishEmpty:SetText("No catches here yet.\nFish in this zone and they will appear.")
    else
      ui.fishEmpty:SetText("Nothing matches this filter.")
    end
    ui.fishEmpty:Show()
  else
    ui.fishEmpty:Hide()
  end
end


-- =====================================================================
-- FRAME CONSTRUCTION
-- =====================================================================

-- Builds the Fishing Log frames inside the main window. Called once from
-- UI.lua. Stores on ui:
--   ui.fishPanel         container for the whole page
--   ui.fishZoneContent   scroll child holding the zone rows
--   ui.fishScroll        the scrolling area on the right
--   ui.fishContent       its scroll child, holding headings and tiles
--   ui.fishTitle / ui.fishCount / ui.fishBarBG / ui.fishBar   header
--   ui.fishShowBtn       the Show drop-down button
--   ui.fishEmpty         message shown when there is nothing to list
function ns.CreateFishPanel(ui)
  local p = CreateFrame("Frame", nil, ui)
  p:SetPoint("TOPLEFT", 156, -32)
  p:SetPoint("BOTTOMRIGHT", -12, 12)
  ui.fishPanel = p
  p:Hide()   -- UI.lua's Refresh decides when it shows
  p:SetScript("OnHide", function()
    if ns.CloseMenus then ns.CloseMenus() end   -- don't leave a menu floating
  end)

  -- ---- Left: scrolling list of zones ----
  local zs = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  zs:SetPoint("TOPLEFT", 0, 0)
  zs:SetPoint("BOTTOMLEFT", 0, 0)
  zs:SetWidth(170)
  local zc = CreateFrame("Frame", nil, zs)
  zc:SetSize(165, 10)
  zs:SetScrollChild(zc)
  ui.fishZoneContent = zc

  -- ---- Right, top: title, count, progress bar, Show drop-down ----
  ui.fishTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.fishTitle:SetPoint("TOPLEFT", 190, -2)

  ui.fishCount = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.fishCount:SetPoint("TOPLEFT", 190, -26)

  ui.fishBarBG = p:CreateTexture(nil, "BACKGROUND")
  ui.fishBarBG:SetColorTexture(1, 1, 1, 0.12)
  ui.fishBarBG:SetPoint("TOPLEFT", 190, -46)
  ui.fishBarBG:SetSize(480, 6)

  ui.fishBar = p:CreateTexture(nil, "ARTWORK")
  ui.fishBar:SetColorTexture(0.2, 0.6, 1, 1)
  ui.fishBar:SetPoint("TOPLEFT", 190, -46)
  ui.fishBar:SetSize(1, 6)

  ui.fishShowBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  ui.fishShowBtn:SetSize(120, 22)
  ui.fishShowBtn:SetPoint("TOPRIGHT", -4, -2)
  ui.fishShowBtn:SetScript("OnClick", function(self)
    if not ns.ShowChoiceMenu then return end   -- drop-down helper lives in PageHunt.lua
    ns.ShowChoiceMenu(self, SHOW_CHOICES, ns.Settings().fishShow, function(key)
      ns.Settings().fishShow = key
      ns.Refresh()
    end)
  end)

  -- ---- Right: scrolling sections and tiles ----
  local sc = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 186, -60)
  sc:SetPoint("BOTTOMRIGHT", -26, 0)
  local content = CreateFrame("Frame", nil, sc)
  content:SetSize(500, 10)
  sc:SetScrollChild(content)
  ui.fishScroll, ui.fishContent = sc, content

  -- Message shown over the list when it is empty
  ui.fishEmpty = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.fishEmpty:SetPoint("CENTER", 90, -20)
  ui.fishEmpty:Hide()
end
--[[
=====================================================================
 UI.lua - main window, left menu, open button, slash command
=====================================================================
 This file loads LAST (see the .toc) because it ties everything
 together: it uses ns.BUILDERS from PageEvents.lua and
 ns.CreateMobPanel / ns.RefreshMobs from PageMobs.lua.

 Functions this file puts on ns for other files to call:
   ns.Refresh()         redraw the current page (safe if window not built)
   ns.RefreshIfOpen()   same, but only if the window is open (used by
                        Capture.lua after each loot)
=====================================================================
]]

local ADDON, ns = ...

-- Left menu entries. To add a page: add an entry here and a matching
-- entry in ns.BUILDERS (PageEvents.lua), unless it has its own custom
-- layout like "mobs".
local PAGES = {
  { key = "hunt",      label = "Hunting Log" },   -- top of the menu
  { key = "mobs",      label = "Mob Drops" },
  { key = "fishing",   label = "Fishing" },
  { key = "quest",     label = "Quest Rewards" },
  { key = "gold",      label = "Gold" },
  { key = "gathering", label = "Gathering" },
}


-- ----- Redraw -----

-- Redraws whichever page is showing and highlights its menu button.
function ns.Refresh()
  local ui = ns.ui
  if not ui then return end          -- window not created yet
  local db = ns.DB()
  if ui.TitleText then ui.TitleText:SetText("LootLog") end   -- the Hunting Log page may change it
  local isMobs = (ns.currentPage == "mobs")
  local isHunt = (ns.currentPage == "hunt")
  -- Show exactly one of: Mob Drops panel, Hunting Log panel, or the
  -- plain text scroll area. Pages with their own layout get a panel.
  ui.mobPanel:SetShown(isMobs)
  ui.huntPanel:SetShown(isHunt)
  ui.scroll:SetShown(not isMobs and not isHunt)
  if isMobs then
    ns.RefreshMobs(db)
  elseif isHunt then
    ns.RefreshHunt(db)
  else
    ui.text:SetText(ns.BUILDERS[ns.currentPage](db))
    ui.content:SetHeight(ui.text:GetStringHeight() + 10)
  end
  -- Keep the active menu button visually pressed
  for key, b in pairs(ui.navButtons) do
    if key == ns.currentPage then b:LockHighlight() else b:UnlockHighlight() end
  end
end

-- Called by Capture.lua after each loot. Only redraws when the window
-- is open, so looting with the window closed costs nothing extra.
function ns.RefreshIfOpen()
  if ns.ui and ns.ui:IsShown() then ns.Refresh() end
end

-- Switch pages from the left menu
local function ShowPage(key)
  ns.currentPage = key
  if ns.ui then ns.ui.scroll:SetVerticalScroll(0) end   -- scroll text pages to top
  ns.Refresh()
end


-- ----- Window construction -----
-- Runs once, the first time the window is opened. Layout numbers are in
-- pixels, measured from the top-left (negative y = downward).

local function CreateUI()
  -- Main window. "BasicFrameTemplateWithInset" is a Blizzard template that
  -- gives the standard frame with title bar and close button.
  local ui = CreateFrame("Frame", "LootLogFrame", UIParent, "BasicFrameTemplateWithInset")
  ns.ui = ui                                   -- share it with the other files
  ui:SetSize(880, 480)
  ui:SetPoint("CENTER")
  ui:SetFrameStrata("HIGH")
  ui:SetMovable(true)
  ui:EnableMouse(true)
  ui:RegisterForDrag("LeftButton")             -- drag the window by left click
  ui:SetScript("OnDragStart", ui.StartMoving)
  ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
  if ui.TitleText then ui.TitleText:SetText("LootLog") end

  -- Left menu: one button per entry in PAGES
  ui.navButtons = {}
  for i, page in ipairs(PAGES) do
    local b = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    b:SetSize(130, 28)
    b:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 34)
    b:SetText(page.label)
    b:SetScript("OnClick", function() ShowPage(page.key) end)
    ui.navButtons[page.key] = b
  end

  -- Scrolling text area for the plain text pages (everything but Mob Drops)
  local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 160, -32)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(650, 10)
  scroll:SetScrollChild(content)
  local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT")
  text:SetWidth(650)
  text:SetJustifyH("LEFT")
  ui.scroll, ui.content, ui.text = scroll, content, text

  -- Mob Drops page frames are built in PageMobs.lua
  ns.CreateMobPanel(ui)

  -- Hunting Log page frames are built in PageHunt.lua
  ns.CreateHuntPanel(ui)

  ui:SetScript("OnShow", function() ns.Refresh() end)   -- redraw on open
  tinsert(UISpecialFrames, "LootLogFrame")              -- lets Esc close it
  ui:Hide()
end

-- Open/close the window, creating it on first use
local function Toggle()
  if not ns.ui then CreateUI() end
  if ns.ui:IsShown() then ns.ui:Hide() else ns.ui:Show() end
end


-- =====================================================================
-- OPEN BUTTON AND SLASH COMMAND
-- =====================================================================

-- Small button on screen that opens the window.
-- Left click = open/close, right-click-drag = move it.
-- (Button position resets on reload; saving it is a future feature.)
local btn = CreateFrame("Button", "LootLogButton", UIParent, "UIPanelButtonTemplate")
btn:SetSize(80, 24)
btn:SetText("LootLog")
btn:SetPoint("TOPLEFT", 20, -20)
btn:SetMovable(true)
btn:RegisterForDrag("RightButton")
btn:SetScript("OnDragStart", btn.StartMoving)
btn:SetScript("OnDragStop", btn.StopMovingOrSizing)
btn:SetScript("OnClick", Toggle)

-- /lootlog          -> open/close the window
-- /lootlog reset    -> wipe all data (saved to disk on next /reload)
SLASH_LOOTLOG1 = "/lootlog"
SlashCmdList.LOOTLOG = function(msg)
  if msg == "reset" then
    -- Wipe the data but keep the user's saved sort/expanded choices
    local keep = LootLogDB and LootLogDB.settings
    local keepClasses = LootLogDB and LootLogDB.classes   -- your class choices
    local keepGone = LootLogDB and LootLogDB.notInGame    -- your "not in game version" flags
    LootLogDB = { events = {}, mobs = {}, settings = keep, classes = keepClasses, notInGame = keepGone }
    wipe(ns.seen)      -- also clear the session guards, or reset
    wipe(ns.counted)   -- would hide the same corpses from being re-logged.
                       -- wipe() empties the table in place; do not replace it
                       -- with {} or other files would keep the old one.
    ns.selectedMob = nil
    ns.huntDetailEntry = nil   -- close any open creature detail page
    ns.NoteVisited()           -- the wipe also cleared visited places; record where you stand
    ns.Refresh()
    print("LootLog: data cleared")
  elseif msg == "debug" then
    ns.HuntDebug()   -- prints what the Hunting Log loaded (PageHunt.lua)
  elseif msg == "kills" then
    -- toggles messages showing how kills are detected (Capture.lua)
    ns.killDebug = not ns.killDebug
    print("LootLog: kill and coin messages " .. (ns.killDebug and "ON" or "OFF") .. ".")
  elseif msg:match("^faction") then
    -- /lootlog faction A | H | all | mine : choose which faction's Hunting Log shows
    local arg = (msg:match("^faction%s+(%S+)") or ""):lower()
    local choices = { mine = "mine", a = "A", alliance = "A", h = "H", horde = "H", all = "all", both = "all" }
    local descriptions = {
      mine = "your character's own faction",
      A = "the Alliance",
      H = "the Horde",
      all = "every faction (everything combined)",
    }
    local choice = choices[arg]
    if choice then
      ns.Settings().huntFaction = choice          -- saved with your settings
      ns.huntPage = 1
      print("LootLog: the Hunting Log now shows " .. descriptions[choice] .. ".")
      ns.Refresh()
    else
      print("LootLog: usage /lootlog faction A | H | all | mine   (now: " ..
            descriptions[ns.Settings().huntFaction] .. ")")
    end
  else
    Toggle()
  end
end
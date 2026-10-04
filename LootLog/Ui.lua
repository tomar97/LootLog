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
  { key = "fishing",   label = "Fishing Log" },
  { key = "quest",     label = "Quest Rewards" },
  { key = "gold",      label = "Gold" },
  { key = "gathering", label = "Gathering" },
  { key = "received",  label = "Received Items" },
  { key = "session",   label = "Session" },
  { key = "help",      label = "Help", bottom = true },   -- pinned to the very bottom of the menu
}


-- ----- Redraw -----

-- Redraws whichever page is showing and highlights its menu button.
function ns.Refresh()
  local ui = ns.ui
  if not ui then return end          -- window not created yet
  local db = ns.ViewDB()   -- this character's data, or everyone's combined
  if ui.TitleText then ui.TitleText:SetText(ns.TitleBase()) end   -- the Hunting Log page may change it
  ui.allCharsCheck:SetChecked(ns.Settings().allChars)
  local isMobs = (ns.currentPage == "mobs")
  local isHunt = (ns.currentPage == "hunt")
  local isFish = (ns.currentPage == "fishing")
  -- Show exactly one of: Mob Drops panel, Hunting Log panel, or the
  -- plain text scroll area. Pages with their own layout get a panel.
  ui.mobPanel:SetShown(isMobs)
  ui.huntPanel:SetShown(isHunt)
  ui.fishPanel:SetShown(isFish)
  ui.scroll:SetShown(not isMobs and not isHunt and not isFish)

  -- Tabs inside a text page (only pages listed in ns.SUBTABS have them)
  local tabs = (not isMobs and not isHunt and not isFish) and ns.SUBTABS and ns.SUBTABS[ns.currentPage] or nil
  local active = tabs and ns.GetSubTab(ns.currentPage)
  for i, b in ipairs(ui.subTabButtons) do
    local t = tabs and tabs[i]
    if t then
      b:SetText(t.label)
      b.key = t.key
      b:Show()
      if t.key == active then b:LockHighlight() else b:UnlockHighlight() end
    else
      b:Hide()
    end
  end
  -- Leave room above the text for the tab buttons
  ui.scroll:ClearAllPoints()
  -- The Help page has its own row of check boxes, so it needs the room too
  local isHelp = (ns.currentPage == "help")
  ui.helpControls:SetShown(isHelp)
  local level = ns.Settings().messageLevel
  ui.reduceCheck:SetChecked(level == "reduced")
  ui.stopCheck:SetChecked(level == "off")
  ui.scroll:SetPoint("TOPLEFT", ui, "TOPLEFT", 160, (tabs or isHelp) and -62 or -32)
  ui.scroll:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -32, 12)
  if isMobs then
    ns.RefreshMobs(db)
  elseif isHunt then
    ns.RefreshHunt(db)
  elseif isFish then
    ns.RefreshFish(db)
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


-- ----- Remembering where you put the window and the button -----
-- Saved in settings.positions[name] = { point, relativePoint, x, y }.

-- Saves where a frame is now.
local function SavePosition(frame, name)
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if point then ns.Settings().positions[name] = { point, relPoint, x, y } end
end

-- Puts a frame back where it was saved (does nothing if nothing is saved).
local function RestorePosition(frame, name)
  local pos = ns.Settings().positions[name]
  if pos then
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  end
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
  ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self, "window")   -- remembered after a reload
  end)
  RestorePosition(ui, "window")    -- put it back where you left it
  if ui.TitleText then ui.TitleText:SetText("LootLog") end   -- (the title is set again by ns.Refresh)

  -- Left menu: one button per entry in PAGES
  ui.navButtons = {}
  local row = 0   -- how many buttons have been stacked from the top so far
  for _, page in ipairs(PAGES) do
    local b = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    b:SetSize(130, 28)
    if page.bottom then
      b:SetPoint("BOTTOMLEFT", 14, 14)                   -- Help sits at the very bottom
    else
      row = row + 1
      b:SetPoint("TOPLEFT", 14, -34 - (row - 1) * 34)    -- the rest stack down from the top
    end
    b:SetText(page.label)
    b:SetScript("OnClick", function() ShowPage(page.key) end)
    ui.navButtons[page.key] = b
  end

  -- "All characters" check box, above the Help button. Ticked: every
  -- character's data is added together and shown read-only. Unticked: only the
  -- character you are playing.
  local check = CreateFrame("CheckButton", nil, ui, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetPoint("BOTTOMLEFT", 10, 48)
  local checkLabel = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
  checkLabel:SetText("All characters")
  check:SetScript("OnClick", function(self)
    ns.Settings().allChars = self:GetChecked() and true or false
    ns.huntPage = 1
    ns.Refresh()
  end)
  check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("All characters")
    GameTooltip:AddLine("Tick to see every character's data added together (read-only). Untick to see only the character you are playing.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.allCharsCheck = check

  -- Chat message options, shown only on the Help page: two check boxes along
  -- the top. "Reduce messages" keeps only stars and similar milestones; "Stop
  -- messages" turns them all off. Unticking either goes back to all messages.
  local hc = CreateFrame("Frame", nil, ui)
  hc:SetPoint("TOPLEFT", 160, -34)
  hc:SetSize(520, 24)
  hc:Hide()
  local hcLabel = hc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hcLabel:SetPoint("LEFT", 0, 0)
  hcLabel:SetText("Chat messages:")
  local function MakeLevelCheck(text, x, level)
    local cb = CreateFrame("CheckButton", nil, hc, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", x, 0)
    local fs = hc:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self)
      ns.SetMessageLevel(self:GetChecked() and level or "all")   -- (Messages.lua)
      ns.Refresh()                                               -- the other box unticks itself
    end)
    return cb
  end
  ui.reduceCheck = MakeLevelCheck("Reduce messages", 110, "reduced")
  ui.stopCheck = MakeLevelCheck("Stop messages", 290, "off")
  ui.helpControls = hc

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

  -- Tab buttons shown above the text on pages that have tabs (for example
  -- Quest Rewards: Rewards / Completed Quests). Which pages have tabs, and
  -- what they are called, is set in ns.SUBTABS (PageEvents.lua).
  ui.subTabButtons = {}
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    b:SetSize(128, 22)
    b:SetPoint("TOPLEFT", 160 + (i - 1) * 132, -34)
    b:SetScript("OnClick", function(self)
      ns.Settings().subtabs[ns.currentPage] = self.key   -- saved with your settings
      ui.scroll:SetVerticalScroll(0)
      ns.Refresh()
    end)
    b:Hide()
    ui.subTabButtons[i] = b
  end

  -- Mob Drops page frames are built in PageMobs.lua
  ns.CreateMobPanel(ui)

  -- Hunting Log page frames are built in PageHunt.lua
  ns.CreateHuntPanel(ui)

  -- Fishing Log page frames are built in PageFishing.lua
  ns.CreateFishPanel(ui)

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
btn:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  SavePosition(self, "button")     -- remembered after a reload
end)
btn:SetScript("OnClick", Toggle)

-- Shows or hides the button to match the saved setting (/lootlog button).
local function ApplyButton()
  if ns.Settings().hideButton then btn:Hide() else btn:Show() end
end

-- Saved settings are not loaded yet while this file runs, so the button's
-- saved position and visibility are applied at login instead.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
  RestorePosition(btn, "button")   -- (the first use of the saved data; old data is migrated here)
  ApplyButton()
  ns.TouchCharacter()              -- note who is playing (creates the character's record)
  if ns.migratedTo then
    print("LootLog now keeps each character's data separately. Your existing data was assigned to " ..
          ns.migratedTo .. ".")
  end
  if ns.newCharacter and not ns.migratedTo and ns.AnnounceNewCharacter then
    ns.AnnounceNewCharacter(ns.newCharacter)   -- a welcome line (Messages.lua)
  elseif ns.AnnounceWelcomeBack then
    ns.AnnounceWelcomeBack()                   -- a recap of the previous session (Messages.lua)
  end
end)

-- /lootlog          -> open/close the window
-- /lootlog reset    -> wipe all data (saved to disk on next /reload)
-- ----- /lootlog reset: asks before wiping anything -----
-- Wipes the logged data of the character you are playing. Everything shared
-- (settings, class choices, flags) and the other characters are kept.
local function DoReset()
  -- Removes this character's data. The other characters, the settings, the
  -- class choices, and the "not in game version" flags are not touched.
  ns.ResetCharacter()
  wipe(ns.seen)      -- also clear the session guards, or reset
  wipe(ns.counted)   -- would hide the same corpses from being re-logged.
                     -- wipe() empties the table in place; do not replace it
                     -- with {} or other files would keep the old one.
  ns.selectedMob = nil
  ns.huntDetailEntry = nil   -- close any open creature detail page
  ns.NoteVisited()           -- the wipe also cleared visited places; record where you stand
  ns.Refresh()
  print("LootLog: data cleared for " .. ns.CharKey())
end

StaticPopupDialogs["LOOTLOG_RESET"] = {
  text = "Clear the LootLog data of THIS character?\n\nThis erases its kills, loot, coin, quests, and the creatures it has met. Your other characters, your settings, class choices, and 'Not in game version' flags are kept. It cannot be undone.",
  button1 = "Clear data",
  button2 = "Cancel",
  OnAccept = function() DoReset() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

SLASH_LOOTLOG1 = "/lootlog"
SlashCmdList.LOOTLOG = function(msg)
  if msg == "reset" then
    StaticPopup_Show("LOOTLOG_RESET")   -- asks first; the question is defined above
  elseif msg == "debug" then
    ns.HuntDebug()   -- prints what the Hunting Log loaded (PageHunt.lua)
  elseif msg:match("^messages") then
    -- /lootlog messages [all|reduced|off]: how chatty LootLog is (Messages.lua).
    -- With no word it steps through all -> reduced -> off -> all.
    local word = (msg:match("^messages%s+(%S+)") or ""):lower()
    local choices = { all = "all", on = "all", full = "all",
                      reduced = "reduced", reduce = "reduced",
                      off = "off", stop = "off" }
    local level = choices[word]
    if not level then
      local order = { all = "reduced", reduced = "off", off = "all" }
      level = order[ns.Settings().messageLevel] or "all"
    end
    ns.SetMessageLevel(level)
    ns.Refresh()   -- keeps the check boxes on the Help page in step
  elseif msg == "all" then
    -- same as the "All characters" check box
    local st = ns.Settings()
    st.allChars = not st.allChars
    ns.huntPage = 1
    print("LootLog: showing " .. (st.allChars and "all characters combined (read-only)." or "this character only."))
    ns.Refresh()
  elseif msg == "characters" then
    -- lists every character with data; * marks the one you are playing
    local list = ns.CharList()
    print("LootLog: " .. #list .. " character(s) with data:")
    for _, c in ipairs(list) do
      print(string.format("  %s %s  (%s)  %d kills  last played %s", c.current and "*" or " ", c.key,
        c.faction or "?", c.kills, c.lastSeen and ns.DateText(c.lastSeen) or "unknown"))
    end
  elseif msg == "button" then
    -- shows or hides the on-screen LootLog button
    local st = ns.Settings()
    st.hideButton = not st.hideButton
    ApplyButton()
    print("LootLog: the on-screen button is now " ..
          (st.hideButton and "hidden. Type /lootlog to open the window." or "shown."))
  elseif msg == "tooltip" then
    -- turns the "killed N times" line on creature tooltips on or off (Tooltips.lua)
    local st = ns.Settings()
    st.tooltipLine = not st.tooltipLine
    print("LootLog: creature tooltip line " .. (st.tooltipLine and "ON" or "OFF") .. ".")
  elseif msg == "kills" then
    -- toggles messages showing how kills are detected (Capture.lua)
    ns.killDebug = not ns.killDebug
    print("LootLog: capture messages (kills, coin, quests, gathering, received items) " .. (ns.killDebug and "ON" or "OFF") .. ".")
    if ns.failedEvents and #ns.failedEvents > 0 then
      print("LootLog: the client refused these events: " .. table.concat(ns.failedEvents, ", "))
    end
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
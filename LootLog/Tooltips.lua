--[[
=====================================================================
 Tooltips.lua - one LootLog line on creature tooltips
=====================================================================
 Hover a hostile or neutral creature and the game's tooltip gets a single
 extra line:
     LootLog: killed 12 times        or        LootLog: not killed yet
 That is all: no drop lists and no percentages, to keep tooltips short.

 /lootlog tooltip turns the line on or off.

 The game changed how addons add tooltip lines over time, so this tries the
 modern way first and the older way second. /lootlog debug says whether
 either one was hooked.
=====================================================================
]]

local ADDON, ns = ...

-- Adds the LootLog line to a unit tooltip. Wrapped in pcall below: if the
-- game hides a value from addons (in combat, for example) the line is simply
-- skipped instead of causing an error.
local function AddLine(tooltip)
  pcall(function()
    if ns.Settings().tooltipLine == false then return end
    if not tooltip.GetUnit then return end
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end   -- hostile / neutral creatures only
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return end

    local m = ns.ViewDB().mobs[tonumber(id)]   -- this character's kills, or everyone's if "All characters" is ticked
    local kills = m and m.kills or 0
    if kills > 0 then
      tooltip:AddLine("LootLog: killed " .. kills .. (kills == 1 and " time" or " times"), 0.6, 0.9, 0.6)
    else
      tooltip:AddLine("LootLog: not killed yet", 0.7, 0.7, 0.7)
    end
  end)
end

-- Hook the tooltip: the modern way if it exists, else the older script hook.
ns.tooltipHooked = false
pcall(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
     and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
      AddLine(tooltip)
    end)
    ns.tooltipHooked = true
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", AddLine)
    ns.tooltipHooked = true
  end
end)


-- ===== NAMES OF OBJECTS YOU POINT AT =====
-- A chest, a mining vein, a herb: when you point at one the game shows its
-- name in the tooltip. We remember the last one, so that loot from an object
-- can be named ("Sturdy Chest") on the Gathering page. Capture.lua reads
-- ns.lastObject when loot opens.
ns.lastObject = nil   -- { name = "Sturdy Chest", time = GetTime() }

local function NoteObjectTooltip(tooltip)
  pcall(function()
    if tooltip.GetUnit then
      local _, unit = tooltip:GetUnit()
      if unit then return end                 -- creatures and players are not objects
    end
    local fs = _G["GameTooltipTextLeft1"]
    local text = fs and fs:GetText()
    if type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then
      ns.lastObject = { name = text, time = GetTime() }
    end
  end)
end

pcall(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
     and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip)
      if tooltip == GameTooltip then NoteObjectTooltip(tooltip) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    -- older way: any tooltip shown in the default spot (not on a button) is a world object
    GameTooltip:HookScript("OnShow", function(tooltip)
      local owner = tooltip.GetOwner and tooltip:GetOwner()
      if owner == UIParent or owner == WorldFrame then NoteObjectTooltip(tooltip) end
    end)
  end
end)
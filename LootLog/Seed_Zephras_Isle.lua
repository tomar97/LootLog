--[[
=====================================================================
 Seed_Zephras_Isle.lua - creatures met in Zephras Isle (starter data)
=====================================================================
 Compiled in game by targeting and mousing over creatures, from your
 SavedVariables upload of 2026-10-03. 14 creatures.

 Unlike the CSV lists, each row carries its OWN faction and hostility:
   fac  = which faction's log it shows in ("H" here: all were met on a Horde
          character, so nothing is known yet about the Alliance side)
   host = "neutral" (yellow badge) or "hostile" (red badge) toward that faction
 Meeting these creatures on an Alliance character adds the Alliance side
 automatically.

 Their classes (Elite, Quest...) are in ClassData.lua.
 To add more creatures, add rows below, or send a newer SavedVariables file.
=====================================================================
]]

local ADDON, ns = ...

local CREATURES = {
  {id=250868, name="Vuldren", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
  {id=250873, name="Juvenile Vuldren", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="neutral"},
  {id=250926, name="Scrawny Ursera", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
  {id=251145, name="Al'Aketh Brute", zones={"Zephras Isle"}, ctype="Humanoid", fac="H", host="neutral"},
  {id=251245, name="Prideclaw", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
  {id=251291, name="Hippogryph Youth", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
  {id=251448, name="Al'Aketh Neophyte", zones={"Zephras Isle"}, ctype="Humanoid", fac="H", host="neutral"},
  {id=251451, name="Al'Aketh Ambusher", zones={"Zephras Isle"}, ctype="Humanoid", fac="H", host="neutral"},
  {id=251559, name="Hoarder", zones={"Zephras Isle"}, ctype="Critter", fac="H", host="neutral"},
  {id=251661, name="Galestrider", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="neutral"},
  {id=254588, name="Windsong Crawler", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="neutral"},
  {id=254589, name="Vulgara the Insatiable", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
  {id=256935, name="Malduko Cloudcrush", zones={"Zephras Isle"}, ctype="Humanoid", fac="H", host="neutral"},
  {id=271712, name="Cloudrunner", zones={"Zephras Isle"}, ctype="Beast", fac="H", host="hostile"},
}

ns.SeedCreatures = ns.SeedCreatures or {}
for _, c in ipairs(CREATURES) do
  table.insert(ns.SeedCreatures, c)   -- fac and host are already set on each row
end
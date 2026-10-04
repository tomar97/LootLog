--[[
=====================================================================
 ClassData.lua - default classes for creatures (Elite, Rare, Boss...)
=====================================================================
 Built from your saved data (SavedVariables upload of 2026-10-03):
   - the classes you chose with the right-click menu in the Hunting Log
   - classes the game reported when you targeted a creature (Elite, Rare, Boss)

 These are DEFAULTS. What you choose in game still wins over them. A creature
 listed here keeps its class even after /lootlog reset or on a fresh install.

 Order of precedence (ns.GetClass in Core.lua):
   1. your choice in game          (saved in your SavedVariables)
   2. critter type -> "critter"
   3. this file                    (ns.SeedClass)
   4. what the game reports        (elite / rare / boss)
   5. "normal"

 To add one: add a line  [npcID] = "elite",  below.
 Classes: normal, elite, rare, boss, critter, quest.
=====================================================================
]]

local ADDON, ns = ...

ns.SeedClass = {
  [808] = "normal",   -- Grik'nir the Cold (your choice)
  [250873] = "normal",   -- Juvenile Vuldren (your choice)
  [250937] = "normal",   -- (name not recorded) (your choice)
  [251115] = "boss",   -- (name not recorded) (your choice)
  [254589] = "elite",   -- Vulgara the Insatiable (reported by the game)
  [256935] = "quest",   -- Malduko Cloudcrush (your choice)
}
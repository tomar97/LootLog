--[[
=====================================================================
 BossData.lua - special messages for individual bosses
=====================================================================
 When you kill a boss for the FIRST time, LootLog prints a message in chat.
 Every boss has the general boss lines in Messages.lua (BOSS_FIRST). A boss
 listed here gets lines of its OWN instead; one is picked at random.

 HOW TO ADD ONE
   [npcID] = {   -- Boss Name
     "First message. {name} becomes the boss's name, in gold.",
     "Second message (optional, more variety).",
   },
 The NPC IDs and names of all the bosses are in BOSSES.md. Send me the lines
 and I will add them here, or add them yourself in the same format.

 Example (not active):
   -- [448] = { "Hogger is down. Somewhere, a gnoll sheds a tear." },
=====================================================================
]]

local ADDON, ns = ...

ns.BossMessages = {
  -- (none yet)
}
--[[
=====================================================================
 ClassData.lua - creatures that are quest creatures (defaults)
=====================================================================
 The designation of a creature (Elite, Rare, Boss) now comes from the creature
 list in Seed_Creatures.lua, so it no longer needs to be listed here. This file
 only holds creatures you have marked as QUEST creatures; the list cannot know
 that. They keep the quest mark after /lootlog reset or on a fresh install.

 What you do in game still wins over this file. To add one by hand:
   [npcID] = "quest",
=====================================================================
]]

local ADDON, ns = ...

ns.SeedClass = {
}
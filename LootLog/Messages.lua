--[[
=====================================================================
 Messages.lua - chat messages when you earn a star
=====================================================================
 Prints a short, randomly chosen line in chat when:
   - you kill a creature for the first time, or earn its 2nd / 3rd star
   - you meet a critter for the first time (its first star is for seeing it)
   - you fish up something for the first time, or earn a fish's 2nd / 3rd star
   - a blue or better item drops (rare and epic drops)
   - you have killed every creature on your list for a zone (zone complete)
   - a character logs in for the first time (a short welcome)
   - you log in again after a break (a recap of the previous session)

 TO ADD OR CHANGE A LINE: every group of lines below is a plain list of text
 in quotes. Add a new line (with a comma at the end) or edit an existing one.
 Inside a line:
   {name}   becomes the creature's name (or the item's link, or the zone's name)
   {count}  becomes the number of kills (only in the "later first star" group)
   {source} becomes where a rare drop came from (only in the drop groups)
 Each time a message is needed, one line of the group is picked at random and
 never the same line twice in a row.

 HOW CHATTY:  the check boxes at the top of the Help page, or
   /lootlog messages [all|reduced|off]
   all      every message
   reduced  only the milestones: stars, blue and epic drops, zone complete
            (the list is MILESTONE below; edit it to change what is kept)
   off      no messages

 WHICH GROUP IS USED
 Creatures (stars come from kills, see ns.HUNT_TIERS_BY_CLASS in Core.lua):
   First kill of a boss .................. BOSS_FIRST (or the lines for that boss in BossData.lua)
   First kill of any other creature ...... FIRST_KILL
   Normal creature's 1st star (10 kills) . STAR1_LATER
   2nd star .............................. STAR2
   3rd star .............................. STAR3
   Quest creature (its one star, on the first kill)  QUEST
   Critters: seen / killed / 5 kills ..... CRITTER_SEEN / CRITTER_KILL / CRITTER_FIVE
 Fishing (stars come from catches, see FishData.lua):
   Fish and Big fish (3 stars) ........... FISH_STAR1 / FISH_STAR2 / FISH_STAR3
   Everything else (1 star, first catch) . FISH_ONE[section name]
=====================================================================
]]

local ADDON, ns = ...

-- ===== CREATURES =====

local FIRST_KILL = {
  "Congrats, you killed {name} for the first time.",
  "First blood on {name}. It won't be the last.",
  "{name} is down. Your first of many, probably.",
  "You killed {name} for the first time. Somewhere, a tiny violin plays.",
  "Congrats! {name} has been added to the list of things that lost to you.",
  "{name} never saw it coming. Well, maybe it did, but too late.",
  "First kill on {name}. A strong start.",
  "{name} is in the logbook now. Not in a good way.",
  "You and {name}: first meeting, last mistake. For {name}, anyway.",
  "One {name} down. The Hunting Log approves.",
}

-- A normal creature's first star comes later (at 10 kills), not on the first kill
local STAR1_LATER = {
  "That's {count} dead {name}. One star, and counting.",
  "{count} kills on {name}. They're starting to take it personally.",
  "One star for {name}. You keep coming back, don't you?",
  "{count} kills of {name}. That's one star and a reputation.",
  "Persistence pays: {name}, {count} times over. One star.",
  "At {count} kills, {name} has become a regular. One star earned.",
  "{name} again and again: {count} down. One star for the grind.",
  "One star for {name}. {count} kills is either dedication or a grudge.",
}

local STAR2 = {
  "What did {name} ever do to you? Actually, they probably deserved it.",
  "Two stars for {name}. This is starting to look like a grudge.",
  "Another pile of {name} gone. Do they owe you money?",
  "{name} again? At this point it's a hobby.",
  "Two stars for {name}. At this point, you two have history.",
  "{name} keeps showing up and you keep winning. Two stars.",
  "Another milestone on {name}: two stars. Is this personal?",
  "Two stars: {name} should really consider a career change.",
  "The {name} population is feeling the pressure. Two stars.",
}

local STAR3 = {
  "Amazing! You clearly hate this guy: {name}.",
  "Three stars for {name}. Is it a vendetta or just a habit?",
  "{name} should probably stay home. Three stars, you monster.",
  "{name} has your face on its wanted posters. Three stars!",
  "Three stars for {name}. They have a poster of you in their nightmares.",
  "{name} is thoroughly farmed. Three stars, and zero remorse.",
  "Completionist! {name} is fully starred.",
  "{name}: three stars. You might need a hobby. Or a bigger target.",
  "Maximum dedication: {name} is now a three-star problem for them.",
}

-- Quest creatures have a single star, earned on the first kill
local QUEST = {
  "{name} deserved it. Enough said.",
  "{name}, down for good. Some stories only need one chapter.",
  "Quest target down: {name}. They had it coming.",
  "This guy deserved it. Enough said. ({name})",
  "{name} is down. The quest log nods in approval.",
  "{name} was marked for a reason. Mission accomplished.",
  "Quest target {name}: handled. Who's next?",
  "Another name crossed off: {name}. They won't be missed.",
  "{name} deserved it. The quest giver will be thrilled.",
}

local CRITTER_SEEN = {
  "A new critter: {name}. Adorable. Try not to get attached.",
  "You spotted {name}. It has no idea how much trouble it's in.",
  "{name} spotted. First star! Nobody asked it to be that cute.",
  "Spotted a critter: {name}. It's too cute to fight. Allegedly.",
  "{name} is out and about. A new face in the wilderness.",
  "Tiny creature alert: {name}. First star for noticing.",
  "You've met {name}. It looks harmless. It probably is.",
  "A wild {name} appeared. It doesn't seem worried.",
}

local CRITTER_KILL = {
  "You killed {name}, a critter. Hope you're proud of yourself.",
  "{name} had a family, you know. Probably.",
  "Second star for {name}. The critter union will hear about this.",
  "{name} down. The wildlife will remember this.",
  "You squashed a {name}. Heroic, truly.",
  "One {name} less in the world. Somebody had to do it.",
  "{name}: defeated. That's two stars and a bit of guilt.",
  "A critter falls. {name} never stood a chance.",
}

local CRITTER_FIVE = {
  "Five of {name} down. The wildlife is filing complaints.",
  "Three stars for {name}: the terror of the small and fluffy.",
  "That's five {name}. Seek help. Or more critters.",
  "Five {name} gone. The critter council demands answers.",
  "{name} extinction event in progress. Three stars.",
  "Three stars for {name}. You've earned the title Critter Menace.",
  "Five {name} later, you're a legend among the small and furry.",
  "{name} wants a word with you. Five kills, three stars.",
}

-- A boss killed for the first time. A boss that has lines of its own in
-- BossData.lua uses those instead; every other boss uses these.
local BOSS_FIRST = {
  "BOSS DOWN: {name}! First kill, and a big one.",
  "{name} has fallen for the first time. That one earned a pause.",
  "You killed {name}, a boss. Take a moment. Then loot.",
  "The boss {name} is dead. The Hunting Log trembles.",
  "First blood on a boss: {name}. Legendary behaviour.",
  "{name} thought it was safe. It wasn't.",
  "Victory! {name} was a boss, and now it's history.",
  "A boss has fallen: {name}. Time for a bit of loot.",
}

-- ===== FISHING =====

-- Fish and Big fish (three stars)
local FISH_STAR1 = {
  "{name}: What the heck is that? And it came out of the water?",
  "{name}: You reel it in, and it stares right back. Weird.",
  "{name}: Well, that's new. Is it supposed to be that color?",
  "{name}: Well, that's a new one for the net.",
  "{name}: Something just bit. This one looks different.",
  "{name}: Is that a fish? It's certainly fish-adjacent.",
  "{name}: Out of the water and into the history books.",
  "{name}: First catch of its kind. Don't make it a habit.",
}

local FISH_STAR2 = {
  "{name}: Oh boy, not this guy again. Don't you know I'm fishing for something better?",
  "{name}: We meet again. The water keeps sending you its leftovers.",
  "{name}: Second star. I'm starting to think they're following me.",
  "{name}: You again. The water must like you.",
  "{name}: Second star. They should send you a thank-you note.",
  "{name}: It keeps biting. So do you.",
  "{name}: At this rate the lake will be empty by Tuesday.",
  "{name}: A regular. You should name it.",
}

local FISH_STAR3 = {
  "{name}: At first I didn't know you, then I knew you too well. Now though, I think our friendship will last forever. At least until I eat ya.",
  "{name}: Three stars. We've been through so much together. Mostly you being hooked.",
  "{name}: Old friend! Dinner's on me. Actually, dinner is you.",
  "{name}: Three stars. You and the water have an understanding.",
  "{name}: A true master of this catch.",
  "{name}: A fully starred catch. The fish have started a support group.",
  "{name}: Dinner is served. Again.",
  "{name}: You've caught so many, they should name a pier after you.",
}

-- Everything else has one star, earned on the first catch. These are grouped
-- by the section names in FishData.lua.
local FISH_ONE = {
  ["Gear"] = {
    "{name}: Who threw this away?",
    "{name}: Sweet, even cheaper than the thrift store.",
    "{name}: Somebody's lost gear is your catch of the day.",
    "{name}: Wait, is this armor? In the water? Sure, why not.",
    "{name}: Someone's going to want that back. Too bad.",
    "{name}: The fish are dressing better than you are.",
    "{name}: Armor class: soggy.",
    "{name}: Fishing for compliments? No, for equipment. Fine.",
    "{name}: A free upgrade? Maybe. It's still wet.",
  },
  ["Junk"] = {
    "{name}: Fishing up trash. Truly the hero this water deserves.",
    "{name}: At least it's not a boot. Okay, it's still junk.",
    "{name}: Not every cast is a winner.",
    "{name}: Junk, but it's YOUR junk now.",
    "{name}: Somebody's trash, another's slightly less trash.",
    "{name}: The sea giveth, and the sea giveth junk.",
    "{name}: At least you cleaned up the water a little.",
  },
  ["Containers and bags"] = {
    "{name}: Ooh, something to open! Please contain something good.",
    "{name}: Something's inside. Something is always inside.",
    "{name}: Something is rattling inside.",
    "{name}: A container! Please be full of gold.",
    "{name}: Waterlogged, but still worth opening.",
    "{name}: A surprise box from the deep.",
    "{name}: Opening this is the best part of fishing.",
  },
  ["Recipes and patterns"] = {
    "{name}: A recipe, from the water. Somebody had a messy kitchen.",
    "{name}: Waterlogged, but still readable. Mostly.",
    "{name}: Someone's recipe book took a swim.",
    "{name}: Knowledge from the deep. Dry it off first.",
    "{name}: Crafters will love this. After it dries.",
    "{name}: A new recipe, courtesy of the lake.",
    "{name}: The ink is still holding up. Impressive.",
  },
  ["Potions and scrolls"] = {
    "{name}: Waterlogged but still usable, probably.",
    "{name}: Somebody dropped their supplies. Finders keepers.",
    "{name}: Still sealed. Probably still good.",
    "{name}: Potion in a bottle, bottle in the water. Neat.",
    "{name}: The cork held. Nice.",
    "{name}: Somebody's emergency stash, now yours.",
    "{name}: Fresh from the depths and surprisingly intact.",
  },
  ["Materials"] = {
    "{name}: Raw materials, fresh from the depths. Crafters rejoice.",
    "{name}: Not a fish, but your crafting friends will take it.",
    "{name}: Fresh material from the water. The crafters smile.",
    "{name}: Handy. Possibly valuable. Definitely damp.",
    "{name}: Crafting ingredient detected.",
    "{name}: A little something for the workbench.",
    "{name}: Useful stuff doesn't always have fins.",
  },
  ["Food, drink and reagents"] = {
    "{name}: Is that edible? Only one way to find out.",
    "{name}: Dinner, or at least a snack.",
    "{name}: Lunch is served.",
    "{name}: Dinner, straight from the water.",
    "{name}: Edible? Probably. Delicious? We'll see.",
    "{name}: A fine addition to the pantry.",
    "{name}: Breakfast fish. You can't beat it.",
  },
  ["Quest fish and items"] = {
    "{name}: A quest catch! The fish had one job.",
    "{name}: That should make somebody happy.",
    "{name}: This one has someone's name on it.",
    "{name}: Quest material, delivered by the water.",
    "{name}: Somebody is going to be very happy.",
    "{name}: Right on cue. The quest log approves.",
    "{name}: The lake knew exactly what you needed.",
  },
}
local FISH_ONE_DEFAULT = {
  "{name}: Something new from the water. Mark it down.",
  "{name}: Well, that's a first.",
  "{name}: Something odd came up. You're not sure what it is.",
  "{name}: A catch for the books.",
  "{name}: New item recorded. The water is full of surprises.",
  "{name}: Not what you were fishing for, but it counts.",
  "{name}: Added to your collection.",
}


-- =====================================================================
-- HELPERS
-- =====================================================================

local lastPick = {}   -- group -> the line used last time, so a line never repeats back to back

-- Picks a random line from a group.
local function Pick(group)
  local n = #group
  local i = math.random(n)
  if n > 1 and lastPick[group] == i then i = (i % n) + 1 end
  lastPick[group] = i
  return group[i]
end

-- Prints one message in chat. text uses {name} and {count} (see the top).
-- name should already be coloured or be an item link.
local function Say(group, name, count, source)
  local text = Pick(group)
  text = text:gsub("{name}", function() return name end)
  text = text:gsub("{count}", function() return tostring(count or "") end)
  text = text:gsub("{source}", function() return source or "" end)
  print("|cffffd100LootLog|r  " .. text)
end

-- False when the user has turned the messages off (/lootlog messages).
-- The kinds of message that still appear in REDUCED mode: the milestones.
-- Move a kind in or out of this list to change what "Reduce messages" keeps.
--   star  = creature and fish stars, a critter's first star
--   zone  = zone complete
--   drop  = blue and epic drops
-- Not listed (so only in "all" mode): the welcome for a new character, the
-- recap of the previous session at login, and the line after selling to a vendor.
local MILESTONE = { star = true, zone = true, drop = true }

-- Should a message of this kind be printed? Depends on the chat message level
-- (ns.Settings().messageLevel): "all", "reduced" (milestones only), or "off".
local function Enabled(kind)
  local level = ns.Settings().messageLevel
  if level == "off" then return false end
  if level == "reduced" then return MILESTONE[kind] == true end
  return true
end

-- A creature name in gold, so it stands out in the message.
local function Gold(name)
  return "|cffffd100" .. name .. "|r"
end


-- ===== DROPS AND ZONES =====

-- Blue drops
local RARE_DROP = {
  "Rare drop! {name} from {source}.",
  "Ooh, blue! {name} dropped from {source}.",
  "{source} was holding out on you: {name}.",
  "Blue! {source} coughed up {name}.",
  "{name} from {source}. A nice find.",
  "{source} dropped {name}. Your lucky day.",
  "Rare loot: {name}, courtesy of {source}.",
  "{name} just fell out of {source}. Keep it safe.",
}

-- Purple and better drops
local EPIC_DROP = {
  "EPIC drop! {name} from {source}. Go ahead, scream.",
  "Purple! {name} from {source}. Is this real life?",
  "{source} gave up {name}. Frame this moment.",
  "PURPLE! {name} from {source}! Tell your friends!",
  "{source} dropped {name}. Quick, check your bags again.",
  "Epic loot: {name}. {source} didn't even see it coming.",
  "{name} from {source}. Nobody will believe you.",
  "Is that {name}? From {source}? Take a screenshot!",
}

-- Every creature on your list for a zone is down ({name} is the zone)
local ZONE_DONE = {
  "Zone complete! Every creature on your list in {name} is down.",
  "{name} is clear. Not a creature left standing on your list.",
  "You've killed everything on your list in {name}. Time for a bigger world.",
  "{name} is yours. Every last creature on the list.",
  "Zone complete: {name}. The locals are thoroughly outclassed.",
  "You've cleared {name}. Time to find a new playground.",
  "{name}: completed. Nothing left to hunt here.",
  "Everything in {name} has met you. Everything.",
}

-- A character logs in for the first time ({name} is the character)
local NEW_CHARACTER = {
  "New character on the books: {name}. Clean slate, empty logs, endless possibilities.",
  "{name} joins the log. Nothing killed yet. Give it time.",
  "Fresh start for {name}. The creatures of this world have no idea what's coming.",
  "Welcome, {name}. Your first page is blank. Go fill it with something small and furry.",
  "{name} steps into the world. The logbook is ready.",
  "A new adventurer: {name}. Everything starts here.",
  "Welcome to the log, {name}. Don't make us regret it.",
  "{name} has arrived. Time to start filling up the pages.",
  "First login for {name}. The creatures are nervous already.",
}

-- Closing a vendor window after selling ({source} is the gold, with coin pictures)
local SALE = {
  "Vendor visit over. {source} richer. Cha-ching.",
  "You sold your haul for {source}. The vendor looks pleased.",
  "{source} in your pocket. The vendor will resell your junk at triple the price.",
  "{name} paid {source} for your junk. Haggling skills: zero.",
  "Sold to {name} for {source}. They already know what to resell it for.",
  "{name} bought your goods for {source}. Everyone wins.",
  "{source} richer after visiting {name}. Business is business.",
  "Lighter bags, heavier purse: {source} from {name}.",
  "Sold to {name} for {source}. You drove a hard bargain. Or not.",
  "{name} paid {source}. Time to buy something shiny.",
}

-- Welcome back at login, with a recap of the previous session
-- ({count} is its kills, {source} is its items, for example "340 items looted")
local WELCOME_BACK = {
  "Welcome back! Last session: {count} kills and {source}. Let's beat that.",
  "Back for more. Last time: {count} kills, {source}. The creatures remember.",
  "Last session: {count} kills, {source}. Not bad. Not great. Go again.",
  "Back again! Last session: {count} kills, {source}. Let's go.",
  "Welcome back. Last time: {count} kills and {source}. Beat that.",
  "The world missed you. Last session: {count} kills, {source}.",
  "Last time you got {count} kills and {source}. Still got it?",
  "Another day, another hunt. Last session: {count} kills, {source}.",
}

-- What LootLog says when you change the message level
local MODE_ALL = {
  "Full chat mode: every star, drop, and bit of nonsense is back.",
  "All messages on. Brace yourself.",
  "The commentary returns.",
  "Back to full volume. Hope you're ready.",
  "All messages on. The peanut gallery is back.",
  "I was waiting for this. Full commentary mode.",
  "Everything on. Every milestone, every comment.",
  "Chatty mode activated. Don't say I didn't warn you.",
}
local MODE_REDUCED = {
  "Quiet mode: only stars, rare drops, and zone clears from now on.",
  "Fine. I'll only speak up for the big moments.",
  "Reduced chatter. I'll save my wit for milestones.",
  "Quiet mode: just the highlights.",
  "I'll keep it short. Milestones only.",
  "Dialing it down. Stars, rare drops, and zone clears only.",
  "Less chatter, same drama. Milestones only.",
  "Understood. I'll speak when it's important.",
}
local MODE_OFF = {
  "Silence. I'll judge you in private.",
  "Messages off. The creatures will never know.",
  "Okay, okay, I'll stop talking.",
  "Going quiet. Your secrets are safe with me.",
  "Silent mode. I'll just keep the books.",
  "Messages off. I'll be over here, judging silently.",
  "Zipped lips. The log still works, though.",
  "Fine. No more commentary. Enjoy the silence.",
}

-- A zone needs at least this many creatures on your list to count as complete
local MIN_ZONE_CREATURES = 5

-- Checks whether the creature you just killed (for the first time) completed
-- any zone it belongs to. "Complete" means: every creature on your list for
-- that zone has been killed at least once. The list is the starter lists for
-- your faction plus the creatures you have met there. Critters and creatures
-- you marked "Not in game version" are left out. Each zone is announced once.
local function CheckZoneComplete(db, npcID)
  if not Enabled("zone") then return end   -- (a zone completed while its messages are off is simply not announced)
  local myFac = ns.PlayerFaction()

  -- The zones this creature belongs to
  local zones = {}
  local row = ns.SeedRow(npcID)
  if row then for _, z in ipairs(row.zones) do zones[z] = true end end
  local k = db.known and ns.GetKnown(db, npcID)
  if k and k.zones then for z in pairs(k.zones) do zones[z] = true end end
  local m = db.mobs[npcID]
  if m and m.zones then for z in pairs(m.zones) do zones[z] = true end end

  db.zonesDone = db.zonesDone or {}
  for zone in pairs(zones) do
    if not db.zonesDone[zone] then
      -- Everyone on your list for this zone
      local members = {}   -- creature ID -> creature type
      for _, c in ipairs(ns.SeedCreatures or {}) do
        local inZone = false
        for _, z in ipairs(c.zones) do
          if z == zone then inZone = true; break end
        end
        if inZone and (not myFac or ns.SeedHas(c, myFac)) then members[c.id] = c.ctype or "" end
      end
      for id in pairs(db.known or {}) do
        local kk = ns.GetKnown(db, id)
        if kk and kk.zones and kk.zones[zone] and (not kk.fac or not myFac or kk.fac[myFac]) then
          members[id] = members[id] or kk.ctype or ""
        end
      end

      -- How many are there, and how many have you killed?
      local total, killed = 0, 0
      for id, ctype in pairs(members) do
        if not ns.IsNotInGame(db, id) and ns.GetClass(db, id, ns.IsCritterType(ctype)) ~= "critter" then
          total = total + 1
          local mm = db.mobs[id]
          if mm and mm.kills > 0 then killed = killed + 1 end
        end
      end

      if total >= MIN_ZONE_CREATURES and killed == total then
        db.zonesDone[zone] = time()   -- remember, so it is only announced once
        Say(ZONE_DONE, Gold(zone))
      end
    end
  end
end


-- =====================================================================
-- CALLED FROM Capture.lua
-- =====================================================================

-- You killed a creature. killsAfter is its kill count including this kill;
-- seenBefore says whether you had met it before (a critter's first star is
-- for seeing it, so that decides whether this kill also earns that star).
function ns.AnnounceKill(npcID, name, killsAfter, seenBefore)
  if not Enabled("star") then return end
  local db = ns.DB()
  local class = ns.GetClass(db, npcID, ns.IsCritterType(ns.CreatureCtype(db, npcID)))
  local before = ns.StarsFor(killsAfter - 1, class, seenBefore)
  local after = ns.StarsFor(killsAfter, class, true)
  name = Gold(name or ("creature " .. npcID))

  if class == "quest" then
    if killsAfter == 1 then Say(QUEST, name) end   -- the first kill earns its one star
  elseif class == "critter" then
    if after > before then
      -- killing a critter earns at least its 2nd star (the 1st is for seeing it)
      Say(after >= 3 and CRITTER_FIVE or CRITTER_KILL, name)
    end
  elseif class == "boss" and killsAfter == 1 then
    -- A boss killed for the first time gets a special line. A boss with lines of
    -- its own in BossData.lua uses those; every other boss uses the general ones.
    local own = ns.BossMessages and ns.BossMessages[npcID]
    Say((own and #own > 0) and own or BOSS_FIRST, name)
  elseif killsAfter == 1 then
    Say(FIRST_KILL, name)                            -- covers the 1st star on Elite / Rare too
  elseif after > before then
    if after == 1 then Say(STAR1_LATER, name, killsAfter)
    elseif after == 2 then Say(STAR2, name)
    else Say(STAR3, name) end
  end

  -- A first kill is the only kill that can complete a zone
  if killsAfter == 1 then CheckZoneComplete(db, npcID) end
end

-- You closed a vendor window after selling things for `copper` in total.
-- Not a milestone, so it only prints in "all" mode.
function ns.AnnounceSale(copper, vendorName)
  if not Enabled("sale") then return end
  Say(SALE, Gold(vendorName or "the vendor"), nil, ns.FormatMoney(copper))
end

-- Login recap of the previous session. Skipped after a quick reload (under 10
-- minutes since the last session ended) so reloading does not spam chat.
function ns.AnnounceWelcomeBack()
  if not Enabled("recap") then return end
  local prev = ns.DB().lastSession
  if not prev or time() - prev.endTime < 600 then return end
  Say(WELCOME_BACK, "", prev.kills, prev.items .. " items looted")
end

-- Sets how chatty LootLog is: "all", "reduced" (stars and similar milestones
-- only), or "off". Says one line about the change, whatever the new level is,
-- so you can see it worked.
function ns.SetMessageLevel(level)
  if level ~= "reduced" and level ~= "off" then level = "all" end
  ns.Settings().messageLevel = level
  Say(level == "off" and MODE_OFF or (level == "reduced" and MODE_REDUCED or MODE_ALL))
end

-- A character logged in for the first time. key is "Name-Realm".
function ns.AnnounceNewCharacter(key)
  if not Enabled("welcome") then return end
  Say(NEW_CHARACTER, Gold((key:match("^(.-)%-") or key)))
end

-- A blue or better item dropped. quality is 3 (rare) or higher (epic and up);
-- source is where it came from in words, for example the creature's name.
function ns.AnnounceDrop(link, quality, source)
  if not Enabled("drop") then return end
  Say(quality >= 4 and EPIC_DROP or RARE_DROP, link, nil, Gold(source or "somewhere"))
end

-- You met a creature for the first time. Only critters have a star for that.
function ns.AnnounceSeen(npcID, name, ctype)
  if not Enabled("star") then return end
  if not ns.IsCritterType(ctype) then return end
  local db = ns.DB()
  if ns.GetClass(db, npcID, true) ~= "critter" then return end   -- you may have set it to something else
  Say(CRITTER_SEEN, Gold(name or ("creature " .. npcID)))
end

-- You fished something up. amount is how many just arrived. Stars count your
-- catches in all zones added together.
function ns.AnnounceFish(itemID, amount)
  if not Enabled("star") then return end
  local db = ns.DB()
  local tiers, section = ns.FishTiers(itemID)
  local total = ns.FishTotal(db, itemID)
  local before = ns.FishStarCount(tiers, total - amount)
  local after = ns.FishStarCount(tiers, total)
  if after <= before then return end

  local link = (db.items and db.items[itemID]) or ("item " .. itemID)
  if #tiers == 1 then
    Say(FISH_ONE[section] or FISH_ONE_DEFAULT, link)
  elseif after == 1 then Say(FISH_STAR1, link)
  elseif after == 2 then Say(FISH_STAR2, link)
  else Say(FISH_STAR3, link) end
end
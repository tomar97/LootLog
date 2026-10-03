--[[
=====================================================================
 Seed_A_Neutral.lua - creatures NEUTRAL to the Alliance (starter data)
=====================================================================
 Source: your "neutral to Alliance" CSV. 255 unique creatures
 (the CSV listed every creature three times).

 These creatures show in the Hunting Log of Alliance characters, greyed
 out until killed. Creatures you meet in game are added on top of this
 automatically, so this list does not need to be complete.

 Fields: id = NPC ID, name, zones = zone names (matching ZoneData.lua),
         ctype = creature type from the CSV.
 Critters and Battle Pets go on the Critters tab (Battle Pets do not
 exist in this version, so they count as critters).

 Zone names were matched to your zone list. Renamed for matching:
   Northern Barrens -> The Barrens, Northern Stranglethorn -> Stranglethorn Vale,
   Mount Hyjal -> Hyjal, Temple of Ahn'Qiraj -> Ahn'Qiraj,
   Upper Blackrock Spire -> Blackrock Spire, Arathi Blizzard -> Arathi Basin
 Locations NOT in your zone list were dropped (count in brackets):
--   The Culling of Stratholme  (6)
--   Howling Fjord  (5)
--   Utgarde Pinnacle  (3)
--   Gilneas  (2)
--   Drak'Tharon Keep  (2)
--   Highmountain Drustvar  (2)
--   Twilight Highlands  (2)
--   Sholazar Basin  (2)
--   Drustvar  (2)
--   Utgarde Keep  (2)
--   Ruins of Gilneas  (1)
--   The Deaths of Chromie  (1)
--   Howling Fjord Gilneas Gilneas  (1)
--   Gilneas Northshire  (1)
--   Gilneas The Lost Isles Gilneas  (1)
--   Spires of Arak Tanaan Jungle  (1)
--   Zul'Drak  (1)
--   Magisters' Terrace  (1)
--   Gilneas Tol Barad Peninsula  (1)
--   Valley of the Four Winds  (1)
--   Dragonblight  (1)
--   Borean Tundra  (1)
--   The Lost Isles  (1)
--   Spires of Arak  (1)
--   Gundrak  (1)
--   Drak'Tharon Keep Ahn'kahet: The Old Kingdom Gilneas The Forge of Souls Icecrown Citadel Halls of Reflection Stormheim Kings' Rest  (1)
--   Bloodmaul Slag Mines  (1)
--   Azjol-Nerub Ahn'kahet: The Old Kingdom Kezan Gilneas  (1)
--   Icecrown Citadel  (1)
--   Tanaan Jungle  (1)
--   The Waking Shores  (1)
--   Gundrak Tol Barad  (1)
--   Drak'Tharon Keep Halls of Stone Ahn'kahet: The Old Kingdom Kezan The Forge of Souls Icecrown Citadel Twilight Highlands Frostwall Lunarfall  (1)
--   Val'sharah Drustvar  (1)
--   Zuldazar Drustvar Stormsong Valley  (1)
--   Broken Shore  (1)
 Creatures left with no zone: 18 (they show under "All zones" only).
 The name "[Deprecated for 4.x]" was removed from one creature's name.

 To add more seed lists later (Horde, hostile...), copy this file, change
 the faction and hostility at the bottom, and list it in LootLog.toc.
=====================================================================
]]

local ADDON, ns = ...

local CREATURES = {
  {id=38, name="Two-Bit Thug", zones={}, ctype="Humanoid"},
  {id=113, name="Stonetusk Boar", zones={"Elwynn Forest"}, ctype="Beast"},
  {id=119, name="Longsnout", zones={"Elwynn Forest"}, ctype="Beast"},
  {id=157, name="Goretusk", zones={"Westfall"}, ctype="Beast"},
  {id=299, name="Young Wolf", zones={"Elwynn Forest"}, ctype="Beast"},
  {id=330, name="Princess", zones={"Elwynn Forest"}, ctype="Beast"},
  {id=428, name="Dire Condor", zones={"Redridge Mountains"}, ctype="Beast"},
  {id=454, name="Young Goretusk", zones={"Westfall"}, ctype="Beast"},
  {id=524, name="Rockhide Boar", zones={"Elwynn Forest"}, ctype="Beast"},
  {id=547, name="Great Goretusk", zones={"Redridge Mountains"}, ctype="Beast"},
  {id=620, name="Chicken", zones={"Duskwood","Elwynn Forest","The Barrens","Westfall","Redridge Mountains","Tirisfal Glades","Azuremyst Isle","Shattrath City"}, ctype="Critter"},
  {id=704, name="Ragged Timber Wolf", zones={"Dun Morogh","Coldridge Valley"}, ctype="Beast"},
  {id=705, name="Ragged Young Wolf", zones={"Dun Morogh","Coldridge Valley"}, ctype="Beast"},
  {id=706, name="Frostmane Troll Whelp", zones={"Dun Morogh","Coldridge Valley"}, ctype="Humanoid"},
  {id=707, name="Rockjaw Trogg", zones={}, ctype="Humanoid"},
  {id=708, name="Small Crag Boar", zones={"Dun Morogh","Coldridge Valley"}, ctype="Beast"},
  {id=724, name="Burly Rockjaw Trogg", zones={}, ctype="Humanoid"},
  {id=808, name="Grik'nir the Cold", zones={"Dun Morogh","Coldridge Valley"}, ctype="Humanoid"},
  {id=830, name="Sand Crawler", zones={"Azshara","Westfall"}, ctype="Beast"},
  {id=831, name="Sea Crawler", zones={"Westfall"}, ctype="Beast"},
  {id=832, name="Unbound Cyclone", zones={"Westfall"}, ctype="Elemental"},
  {id=883, name="Deer", zones={"Elwynn Forest","Western Plaguelands","Arathi Highlands","The Hinterlands","Silverpine Forest","Darkshore","Hillsbrad Foothills","Ashenvale","Feralas","Moonglade","Darnassus","Dire Maul","Blade's Edge Mountains","Azuremyst Isle","Shadowglen"}, ctype="Beast"},
  {id=890, name="Fawn", zones={"Elwynn Forest","Teldrassil","Shadowglen"}, ctype="Critter"},
  {id=946, name="Frostmane Novice", zones={"Dun Morogh","Coldridge Valley"}, ctype="Humanoid"},
  {id=1088, name="Monstrous Crawler", zones={"Swamp of Sorrows"}, ctype="Beast"},
  {id=1125, name="Crag Boar", zones={"Dun Morogh"}, ctype="Beast"},
  {id=1216, name="Shore Crawler", zones={"Westfall"}, ctype="Beast"},
  {id=1412, name="Squirrel", zones={"Wetlands","Elwynn Forest","Azshara","Loch Modan","Darkshore","Ashenvale","Feralas","Moonglade","Stormwind City","Darnassus","Dire Maul","Zul'Aman","Dalaran","Nagrand"}, ctype="Critter"},
  {id=1420, name="Toad", zones={"Swamp of Sorrows","Wetlands","Durotar","Dustwallow Marsh","Silverpine Forest","Hillsbrad Foothills","Ashenvale","Felwood","Orgrimmar","Darnassus","Eversong Woods","Ghostlands","Nagrand","The Steamvault","The Underbog","Black Temple","Shadowglen"}, ctype="Critter"},
  {id=1501, name="Mindless Zombie", zones={"Tirisfal Glades","Deathknell"}, ctype="Undead"},
  {id=1502, name="Wretched Ghoul", zones={"Tirisfal Glades","Deathknell"}, ctype="Undead"},
  {id=1508, name="Young Scavenger", zones={"Tirisfal Glades","Deathknell"}, ctype="Beast"},
  {id=1509, name="Ragged Scavenger", zones={"Deathknell"}, ctype="Beast"},
  {id=1512, name="Duskbat", zones={"Tirisfal Glades","Deathknell"}, ctype="Beast"},
  {id=1513, name="Mangy Duskbat", zones={"Deathknell"}, ctype="Beast"},
  {id=1553, name="Greater Duskbat", zones={"Tirisfal Glades"}, ctype="Beast"},
  {id=1689, name="Scarred Crag Boar", zones={"Dun Morogh","Loch Modan"}, ctype="Beast"},
  {id=1890, name="Rattlecage Skeleton", zones={"Tirisfal Glades","Deathknell"}, ctype="Undead"},
  {id=1916, name="Stephen Bhartec", zones={"Deathknell"}, ctype="Undead"},
  {id=1917, name="Daniel Ulfman", zones={"Deathknell"}, ctype="Undead"},
  {id=1918, name="Karrel Grayves", zones={"Deathknell"}, ctype="Undead"},
  {id=1919, name="Samuel Fipps", zones={"Deathknell"}, ctype="Undead"},
  {id=1933, name="Sheep", zones={"Elwynn Forest","Loch Modan","Redridge Mountains","Silverpine Forest","Hillsbrad Foothills","City","Uldum","Arathi Highlands"}, ctype="Beast"},
  {id=1948, name="Snarlmane", zones={"Silverpine Forest"}, ctype="Undead"},
  {id=1984, name="Young Thistle Boar", zones={"Shadowglen"}, ctype="Beast"},
  {id=1985, name="Thistle Boar", zones={"Teldrassil","Shadowglen"}, ctype="Beast"},
  {id=1988, name="Grell", zones={"Teldrassil","Shadowglen"}, ctype="Demon"},
  {id=1989, name="Grellkin", zones={"Shadowglen"}, ctype="Demon"},
  {id=1995, name="Strigid Owl", zones={"Teldrassil"}, ctype="Beast"},
  {id=1996, name="Strigid Screecher", zones={"Teldrassil"}, ctype="Beast"},
  {id=1997, name="Strigid Hunter", zones={"Teldrassil"}, ctype="Beast"},
  {id=2031, name="Young Nightsaber", zones={"Teldrassil","Shadowglen"}, ctype="Beast"},
  {id=2032, name="Mangy Nightsaber", zones={"Teldrassil","Shadowglen"}, ctype="Beast"},
  {id=2098, name="Ram", zones={"Wetlands","Loch Modan","Arathi Highlands","Hillsbrad Foothills"}, ctype="Beast"},
  {id=2110, name="Black Rat", zones={"Badlands","Duskwood","Wetlands","Dustwallow Marsh","Western Plaguelands","Eastern Plaguelands","Shadowfang Keep","Thousand Needles","Razorfen Downs","Blackrock Spire","The Shattered Halls","The Slave Pens"}, ctype="Critter"},
  {id=2172, name="Strider Clutchmother", zones={"Darkshore"}, ctype="Beast"},
  {id=2233, name="Encrusted Tide Crawler", zones={"Darkshore"}, ctype="Beast"},
  {id=2321, name="Foreststrider Fledgling", zones={"Darkshore"}, ctype="Beast"},
  {id=2408, name="Snapjaw", zones={"Hillsbrad Foothills","Old Hillsbrad Foothills"}, ctype="Beast"},
  {id=2442, name="Cow", zones={"Wetlands","Elwynn Forest","Redridge Mountains","Arathi Highlands","Stormwind City"}, ctype="Beast"},
  {id=2505, name="Saltwater Snapjaw", zones={"The Hinterlands"}, ctype="Beast"},
  {id=2544, name="Southern Sand Crawler", zones={"The Cape of Stranglethorn"}, ctype="Beast"},
  {id=2578, name="Young Mesa Buzzard", zones={"Arathi Highlands"}, ctype="Beast"},
  {id=2579, name="Mesa Buzzard", zones={"Arathi Highlands"}, ctype="Beast"},
  {id=2580, name="Elder Mesa Buzzard", zones={"Arathi Highlands"}, ctype="Beast"},
  {id=2611, name="Fozruk", zones={"Arathi Highlands"}, ctype="Giant"},
  {id=2620, name="Prairie Dog", zones={"The Barrens","Westfall","Arathi Highlands","Mulgore","Desolace","Stonetalon Mountains","Stormwind City","Thunder Bluff","Nagrand","Southern Barrens","Camp Narache"}, ctype="Critter"},
  {id=2749, name="Barricade", zones={"Badlands"}, ctype="Elemental"},
  {id=2755, name="Myzrael", zones={"Arathi Highlands"}, ctype="Elemental"},
  {id=2887, name="Prismatic Exile", zones={"Arathi Highlands"}, ctype="Elemental"},
  {id=2914, name="Snake", zones={"Dustwallow Marsh","Stranglethorn Vale","Westfall","Feralas","Wailing Caverns","Sunken Temple","Maraudon","The Black Morass","Zangarmarsh","The Shattered Halls","The Steamvault","Sethekk Halls"}, ctype="Critter"},
  {id=2952, name="Bristleback Invaders", zones={"Camp Narache"}, ctype="Humanoid"},
  {id=2955, name="Plainstrider", zones={"Camp Narache"}, ctype="Beast"},
  {id=2956, name="Adult Plainstrider", zones={"Mulgore","Thunder Bluff"}, ctype="Beast"},
  {id=2957, name="Elder Plainstrider", zones={"Mulgore","Thunder Bluff"}, ctype="Beast"},
  {id=2972, name="Kodo Calf", zones={"Mulgore"}, ctype="Beast"},
  {id=2973, name="Kodo Bull", zones={"Mulgore"}, ctype="Beast"},
  {id=2974, name="Kodo Matriarch", zones={"Mulgore"}, ctype="Beast"},
  {id=3058, name="Arra'chea", zones={"Mulgore"}, ctype="Beast"},
  {id=3098, name="Mottled Boar", zones={"Durotar","Valley of Trials"}, ctype="Beast"},
  {id=3099, name="Dire Mottled Boar", zones={"Durotar"}, ctype="Beast"},
  {id=3100, name="Elder Mottled Boar", zones={"Durotar"}, ctype="Beast"},
  {id=3101, name="Vile Familiar", zones={"Durotar","Valley of Trials"}, ctype="Humanoid"},
  {id=3102, name="Felstalker", zones={"Durotar"}, ctype="Demon"},
  {id=3106, name="Surf Crawler", zones={"Durotar"}, ctype="Beast"},
  {id=3107, name="Mature Surf Crawler", zones={"Durotar","Echo Isles"}, ctype="Beast"},
  {id=3108, name="Encrusted Surf Crawler", zones={"Durotar"}, ctype="Beast"},
  {id=3124, name="Scorpid Worker", zones={"Dun Morogh","Durotar","Valley of Trials"}, ctype="Beast"},
  {id=3234, name="Lost Barrens Kodo", zones={"The Barrens","Southern Barrens"}, ctype="Beast"},
  {id=3236, name="Barrens Kodo", zones={"The Barrens"}, ctype="Beast"},
  {id=3242, name="Zhevra Runner", zones={"The Barrens"}, ctype="Beast"},
  {id=3244, name="Greater Plainstrider", zones={"The Barrens"}, ctype="Beast"},
  {id=3245, name="Ornery Plainstrider", zones={"The Barrens"}, ctype="Beast"},
  {id=3246, name="Fleeting Plainstrider", zones={"The Barrens"}, ctype="Beast"},
  {id=3248, name="Barrens Giraffe", zones={"The Barrens","Southern Barrens"}, ctype="Beast"},
  {id=3281, name="Sarkoth", zones={"Valley of Trials"}, ctype="Beast"},
  {id=3300, name="Adder", zones={"Blasted Lands","Durotar","The Barrens","Stranglethorn Vale","Hellfire Peninsula","The Underbog","The Slave Pens","Sethekk Halls","Mana-Tombs","Southern Barrens","Valley of Trials","Nagrand"}, ctype="Critter"},
  {id=3426, name="Zhevra Charger", zones={"The Barrens","Southern Barrens"}, ctype="Beast"},
  {id=3444, name="Dig Rat", zones={"Southern Barrens"}, ctype="Critter"},
  {id=3462, name="Elder Barrens Giraffe", zones={"The Barrens"}, ctype="Beast"},
  {id=3474, name="Lakota'mani", zones={}, ctype="Beast"},
  {id=3653, name="Kresh", zones={"Wailing Caverns"}, ctype="Beast"},
  {id=3680, name="Serpentbloom Snake", zones={"Wailing Caverns"}, ctype="Beast"},
  {id=3812, name="Clattering Crawler", zones={"Darkshore","Ashenvale","Blackfathom Deeps"}, ctype="Beast"},
  {id=3814, name="Spined Crawler", zones={"Darkshore","Ashenvale","Blackfathom Deeps"}, ctype="Beast"},
  {id=3815, name="Blink Dragon", zones={"Ashenvale"}, ctype="Dragonkin"},
  {id=3816, name="Wild Buck", zones={"Darkshore","Ashenvale"}, ctype="Beast"},
  {id=3817, name="Shadowhorn Stag", zones={"Ashenvale"}, ctype="Beast"},
  {id=3818, name="Elder Shadowhorn Stag", zones={"Ashenvale"}, ctype="Beast"},
  {id=3835, name="Biletoad", zones={"The Barrens","Wailing Caverns"}, ctype="Critter"},
  {id=3864, name="Fel Steed", zones={"Shadowfang Keep"}, ctype="Beast"},
  {id=3865, name="Shadow Charger", zones={"Shadowfang Keep"}, ctype="Undead"},
  {id=4018, name="Antlered Courser", zones={"Stonetalon Mountains"}, ctype="Beast"},
  {id=4019, name="Great Courser", zones={"Stonetalon Mountains"}, ctype="Beast"},
  {id=4066, name="Nal'taszar", zones={"Stonetalon Mountains"}, ctype="Dragonkin"},
  {id=4067, name="Twilight Runner", zones={"Stonetalon Mountains"}, ctype="Beast"},
  {id=4075, name="Rat", zones={"Swamp of Sorrows","Azshara","Loch Modan","Arathi Highlands","The Hinterlands","Tirisfal Glades","Darkshore","Hillsbrad Foothills","Ashenvale","Desolace","Scarlet Monastery","Sunken Temple","Stormwind City","The Deadmines","Scholomance","Dire Maul","Arathi Basin","Ghostlands","Naxxramas","Karazhan","Nagrand","Terokkar Forest","The Shattered Halls","Sethekk Halls","Dalaran","City","The Cape of Stranglethorn","Deathknell"}, ctype="Critter"},
  {id=4076, name="Roach", zones={"Duskwood","Stranglethorn Vale","Redridge Mountains","Ashenvale","Thousand Needles","Desolace","Razorfen Downs","Undercity","Blackrock Spire","Dire Maul","Ahn'Qiraj","Sethekk Halls","Mana-Tombs","City","The Cape of Stranglethorn"}, ctype="Critter"},
  {id=4166, name="Gazelle", zones={"The Barrens","Mulgore","Desolace","Southern Barrens","Camp Narache"}, ctype="Beast"},
  {id=4388, name="Young Murk Thresher", zones={"Dustwallow Marsh"}, ctype="Beast"},
  {id=4397, name="Mudrock Spikeshell", zones={"Dustwallow Marsh"}, ctype="Beast"},
  {id=4700, name="Aged Kodo", zones={"Desolace"}, ctype="Beast"},
  {id=4701, name="Dying Kodo", zones={"Desolace"}, ctype="Beast"},
  {id=4702, name="Ancient Kodo", zones={"Desolace"}, ctype="Beast"},
  {id=4795, name="Force of Nature", zones={"Feralas"}, ctype="Uncategorized"},
  {id=4952, name="Theramore Combat Dummy", zones={"Dustwallow Marsh"}, ctype="Mechanical"},
  {id=4953, name="Water Snake", zones={"Swamp of Sorrows","Wetlands","Durotar","Stranglethorn Vale","Orgrimmar"}, ctype="Critter"},
  {id=5276, name="Sprite Dragon", zones={}, ctype="Dragonkin"},
  {id=5354, name="Gnarl Leafbrother", zones={"Feralas"}, ctype="Elemental"},
  {id=5431, name="Surf Glider", zones={"Tanaris"}, ctype="Beast"},
  {id=5831, name="Swiftmane", zones={"The Barrens"}, ctype="Beast"},
  {id=5843, name="Slave Worker", zones={"Searing Gorge"}, ctype="Humanoid"},
  {id=5951, name="Hare", zones={"Durotar","Arathi Highlands","The Hinterlands","Valley of Trials"}, ctype="Critter"},
  {id=6109, name="Azuregos", zones={}, ctype="Dragonkin"},
  {id=6145, name="School of Fish", zones={"Durotar","Dustwallow Marsh","Darkshore","Ashenvale","Desolace","Stonetalon Mountains","Hyjal","Maraudon","Eversong Woods","Azuremyst Isle","Echo Isles"}, ctype="Critter"},
  {id=6271, name="Mouse", zones={"Duskwood","Wetlands","Dustwallow Marsh","Westfall","Mulgore","Stonetalon Mountains","Silvermoon City"}, ctype="Critter"},
  {id=6352, name="Coralshell Lurker", zones={"Azshara"}, ctype="Beast"},
  {id=6368, name="Cat", zones={"Elwynn Forest","Arathi Highlands","Silvermoon City","City","Sunstrider Isle"}, ctype="Critter"},
  {id=6466, name="Gamon", zones={"Orgrimmar"}, ctype="Humanoid"},
  {id=6492, name="Rift Spawn", zones={"Undercity","Stormwind City"}, ctype="Elemental"},
  {id=6509, name="Bloodpetal Lasher", zones={"Un'Goro Crater"}, ctype="Elemental"},
  {id=6510, name="Bloodpetal Flayer", zones={"Un'Goro Crater"}, ctype="Elemental"},
  {id=6511, name="Bloodpetal Thresher", zones={"Un'Goro Crater"}, ctype="Elemental"},
  {id=6512, name="Bloodpetal Trapper", zones={"Un'Goro Crater"}, ctype="Elemental"},
  {id=6560, name="Stone Guardian", zones={"Un'Goro Crater"}, ctype="Elemental"},
  {id=6626, name="\"Plucky\" Johnson", zones={}, ctype="Humanoid"},
  {id=6653, name="Huge Toad", zones={"Swamp of Sorrows","Western Plaguelands","Hillsbrad Foothills"}, ctype="Critter"},
  {id=6728, name="Narnie", zones={"Redridge Mountains"}, ctype="Beast"},
  {id=6827, name="Strand Crab", zones={"Swamp of Sorrows","Stranglethorn Vale","Ashenvale","Blackfathom Deeps","The Steamvault","The Cape of Stranglethorn"}, ctype="Critter"},
  {id=7093, name="Vile Ooze", zones={"Felwood"}, ctype="Aberration"},
  {id=7097, name="Ironbeak Owl", zones={"Felwood"}, ctype="Beast"},
  {id=7099, name="Ironbeak Hunter", zones={"Felwood"}, ctype="Beast"},
  {id=7269, name="Scarab", zones={"Zul'Farrak"}, ctype="Beast"},
  {id=7381, name="Silver Tabby Cat", zones={"Elwynn Forest"}, ctype="Battle Pet"},
  {id=7382, name="Orange Tabby Cat", zones={"Elwynn Forest"}, ctype="Battle Pet"},
  {id=7383, name="Black Tabby Cat", zones={"Hillsbrad Foothills"}, ctype="Battle Pet"},
  {id=7384, name="Cornish Rex Cat", zones={"Elwynn Forest"}, ctype="Battle Pet"},
  {id=7385, name="Bombay Cat", zones={"Elwynn Forest"}, ctype="Battle Pet"},
  {id=7386, name="White Kitten", zones={"Stormwind City"}, ctype="Battle Pet"},
  {id=7387, name="Green Wing Macaw", zones={"The Deadmines"}, ctype="Battle Pet"},
  {id=7389, name="Senegal", zones={"The Cape of Stranglethorn"}, ctype="Battle Pet"},
  {id=7390, name="Cockatiel", zones={"The Cape of Stranglethorn"}, ctype="Battle Pet"},
  {id=7391, name="Hyacinth Macaw", zones={"The Cape of Stranglethorn"}, ctype="Battle Pet"},
  {id=7395, name="Undercity Cockroach", zones={"Wetlands","Undercity","Orgrimmar"}, ctype="Battle Pet"},
  {id=7455, name="Winterspring Owl", zones={"Winterspring"}, ctype="Beast"},
  {id=7456, name="Winterspring Screecher", zones={"Winterspring"}, ctype="Beast"},
  {id=7553, name="Great Horned Owl", zones={"Stormwind City","Darnassus"}, ctype="Battle Pet"},
  {id=7554, name="Snowy Owl", zones={"Winterspring"}, ctype="Battle Pet"},
  {id=7555, name="Hawk Owl", zones={"Stormwind City","Darnassus"}, ctype="Battle Pet"},
  {id=7584, name="Wandering Forest Walker", zones={"Feralas"}, ctype="Elemental"},
  {id=8196, name="Occulus", zones={}, ctype="Dragonkin"},
  {id=8211, name="Old Cliff Jumper", zones={"The Hinterlands"}, ctype="Beast"},
  {id=8213, name="Ironback", zones={"The Hinterlands"}, ctype="Beast"},
  {id=8603, name="Carrion Grub", zones={"Eastern Plaguelands"}, ctype="Beast"},
  {id=8605, name="Carrion Devourer", zones={"Eastern Plaguelands"}, ctype="Beast"},
  {id=8761, name="Mosshoof Courser", zones={"Azshara"}, ctype="Beast"},
  {id=8917, name="Quarry Slave", zones={"Blackrock Mountain","Burning Steppes","Searing Gorge"}, ctype="Humanoid"},
  {id=8981, name="Malfunctioning Reaver", zones={"Burning Steppes"}, ctype="Elemental"},
  {id=9178, name="Burning Spirit", zones={"Blackrock Depths"}, ctype="Elemental"},
  {id=9499, name="Plugger Spazzring", zones={"Blackrock Depths"}, ctype="Humanoid"},
  {id=9545, name="Grim Patron", zones={"Blackrock Depths"}, ctype="Humanoid"},
  {id=9547, name="Guzzling Patron", zones={"Blackrock Depths"}, ctype="Humanoid"},
  {id=9554, name="Hammered Patron", zones={"Blackrock Depths"}, ctype="Humanoid"},
  {id=9600, name="Parrot", zones={"Swamp of Sorrows","Stranglethorn Vale","Un'Goro Crater","The Cape of Stranglethorn"}, ctype="Critter"},
  {id=9699, name="Fire Beetle", zones={"Blasted Lands","Blackrock Mountain","Burning Steppes","Searing Gorge","Hyjal","The Shattered Halls"}, ctype="Critter"},
  {id=9700, name="Lava Crab", zones={"Burning Steppes","Searing Gorge"}, ctype="Critter"},
  {id=9776, name="Flamekin Spitter", zones={"Burning Steppes"}, ctype="Demon"},
  {id=9778, name="Flamekin Torcher", zones={"Burning Steppes"}, ctype="Demon"},
  {id=9779, name="Flamekin Rager", zones={"Burning Steppes"}, ctype="Demon"},
  {id=10016, name="Tainted Rat", zones={"Felwood"}, ctype="Critter"},
  {id=10017, name="Tainted Cockroach", zones={"Felwood","Shadowmoon Valley"}, ctype="Critter"},
  {id=10262, name="Opus", zones={"Burning Steppes"}, ctype="Beast"},
  {id=10384, name="Spectral Citizen", zones={"Stratholme"}, ctype="Undead"},
  {id=10385, name="Ghostly Citizen", zones={"Stratholme"}, ctype="Undead"},
  {id=10432, name="Vectus", zones={"Scholomance"}, ctype="Undead"},
  {id=10558, name="Hearthsinger Forresten", zones={"Stratholme"}, ctype="Undead"},
  {id=10600, name="Thontek Rumblehoof", zones={"Mulgore"}, ctype="Humanoid"},
  {id=10685, name="Swine", zones={"Durotar","The Barrens"}, ctype="Critter"},
  {id=10779, name="Infected Squirrel", zones={"Silverpine Forest","Eastern Plaguelands","Bloodmyst Isle"}, ctype="Critter"},
  {id=10780, name="Infected Deer", zones={"Silverpine Forest","Eastern Plaguelands","Bloodmyst Isle"}, ctype="Beast"},
  {id=10817, name="Duggan Wildhammer", zones={"Eastern Plaguelands"}, ctype="Humanoid"},
  {id=10824, name="Death-Hunter Hawkspear", zones={"Eastern Plaguelands"}, ctype="Humanoid"},
  {id=10942, name="Nessy", zones={}, ctype="Beast"},
  {id=10956, name="Naga Siren", zones={}, ctype="Humanoid"},
  {id=10981, name="Frost Wolf", zones={"Alterac Valley"}, ctype="Beast"},
  {id=10990, name="Alterac Ram", zones={"Alterac Valley"}, ctype="Beast"},
  {id=11560, name="Magrami Spectre", zones={"Desolace"}, ctype="Undead"},
  {id=11621, name="Spectral Corpse", zones={"Eastern Plaguelands"}, ctype="Undead"},
  {id=12296, name="Sickly Gazelle", zones={}, ctype="Beast"},
  {id=12298, name="Sickly Deer", zones={}, ctype="Beast"},
  {id=12347, name="Enraged Reef Crawler", zones={"Desolace"}, ctype="Beast"},
  {id=13016, name="Deeprun Rat", zones={}, ctype="Critter"},
  {id=13159, name="James Clark", zones={"Elwynn Forest"}, ctype="Humanoid"},
  {id=13321, name="Small Frog", zones={"Swamp of Sorrows","Duskwood","Elwynn Forest","The Barrens","Loch Modan","Arathi Highlands","Teldrassil","Desolace","Sunken Temple","Darnassus","Maraudon","Dire Maul","Eversong Woods","Ghostlands","Zangarmarsh","The Steamvault","The Slave Pens","Southern Barrens"}, ctype="Critter"},
  {id=13599, name="Stolid Snapjaw", zones={"Maraudon"}, ctype="Beast"},
  {id=13836, name="Burning Blade Nightmare", zones={"Desolace"}, ctype="Demon"},
  {id=13896, name="Scalebeard", zones={"Azshara"}, ctype="Beast"},
  {id=14123, name="Steeljaw Snapper", zones={"Tanaris"}, ctype="Beast"},
  {id=14223, name="Cranky Benj", zones={"Hillsbrad Foothills"}, ctype="Beast"},
  {id=14224, name="7:XT", zones={"Badlands"}, ctype="Mechanical"},
  {id=14273, name="Boulderheart", zones={"Redridge Mountains"}, ctype="Giant"},
  {id=14337, name="Field Repair Bot 74A", zones={}, ctype="Mechanical"},
  {id=14343, name="Olm the Wise", zones={"Felwood"}, ctype="Beast"},
  {id=14355, name="Azj'Tordin", zones={"Feralas"}, ctype="Humanoid"},
  {id=14358, name="Shen'dralar Ancient", zones={"Dire Maul"}, ctype="Undead"},
  {id=14361, name="Shen'dralar Wisp", zones={"Dire Maul"}, ctype="Critter"},
  {id=14364, name="Shen'dralar Spirit", zones={"Dire Maul"}, ctype="Undead"},
  {id=14369, name="Shen'dralar Zealot", zones={"Dire Maul"}, ctype="Humanoid"},
  {id=14371, name="Shen'dralar Provisioner", zones={"Dire Maul"}, ctype="Humanoid"},
  {id=14492, name="Verifonix", zones={"The Cape of Stranglethorn"}, ctype="Humanoid"},
  {id=14881, name="Spider", zones={"Swamp of Sorrows","The Hinterlands","Eastern Plaguelands","Teldrassil","Winterspring","Naxxramas","Karazhan","Shadow Labyrinth","Sethekk Halls","Mana-Tombs","Zul'Aman","Black Temple"}, ctype="Critter"},
  {id=15065, name="Lady", zones={"Arathi Basin"}, ctype="Critter"},
  {id=15066, name="Cleo", zones={"Arathi Basin"}, ctype="Critter"},
  {id=15071, name="Underfoot", zones={"Arathi Basin"}, ctype="Critter"},
  {id=15072, name="Spike", zones={"Arathi Basin"}, ctype="Critter"},
  {id=15168, name="Vile Scarab", zones={"Ruins of Ahn'Qiraj"}, ctype="Beast"},
  {id=15186, name="Murky", zones={"Ironforge","Orgrimmar"}, ctype="Battle Pet"},
  {id=15271, name="Tender", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Elemental"},
  {id=15274, name="Mana Wyrm", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Beast"},
  {id=15294, name="Feral Tender", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Elemental"},
  {id=15333, name="Silicate Feeder", zones={"Ruins of Ahn'Qiraj"}, ctype="Beast"},
  {id=15366, name="Springpaw Cub", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Beast"},
  {id=15367, name="Felendren the Banished", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Humanoid"},
  {id=15372, name="Springpaw Lynx", zones={"Eversong Woods","Sunstrider Isle"}, ctype="Beast"},
  {id=15475, name="Beetle", zones={"Badlands","Stranglethorn Vale","Eastern Plaguelands","Ashenvale","Felwood","Un'Goro Crater","Blackfathom Deeps","Silithus","Ahn'Qiraj","The Cape of Stranglethorn"}, ctype="Critter"},
  {id=15476, name="Scorpid", zones={"Blasted Lands","Burning Steppes","Eastern Plaguelands","Thousand Needles","Silithus","Orgrimmar","Ahn'Qiraj","Hellfire Peninsula","Shadowmoon Valley","Blade's Edge Mountains"}, ctype="Critter"},
  {id=16030, name="Maggot", zones={"The Hinterlands","Hillsbrad Foothills","Ashenvale","Undercity","Ghostlands","Naxxramas","The Underbog"}, ctype="Critter"},
  {id=16068, name="Larva", zones={"Ghostlands","Naxxramas"}, ctype="Critter"},
  {id=16069, name="Gurky", zones={"Ironforge","Orgrimmar"}, ctype="Battle Pet"},
  {id=16114, name="Scarlet Commander Marjhan", zones={}, ctype="Humanoid"},
  {id=16117, name="Plagued Swine", zones={"Eastern Plaguelands"}, ctype="Beast"},
  {id=16131, name="Rohan the Assassin", zones={}, ctype="Humanoid"},
  {id=16132, name="Huntsman Leopold", zones={}, ctype="Humanoid"},
  {id=16133, name="Mataus the Wrathcaster", zones={}, ctype="Humanoid"},
  {id=16998, name="Mr. Bigglesworth", zones={"Naxxramas"}, ctype="Critter"},
}

ns.SeedCreatures = ns.SeedCreatures or {}
for _, c in ipairs(CREATURES) do
  c.fac = "A"            -- shows in the Alliance log (use "H" for Horde, "AH" for both)
  c.host = "neutral"     -- neutral (yellow badge) or "hostile" (red badge) toward that faction
  table.insert(ns.SeedCreatures, c)
end
-- ============================================================
-- Dungeon Teleporter NPC (rewrite of an older teleporter script)
-- NPC entry comes from acore_settings.lua -> dungeonTeleporter.npc (0 = disabled). Any spawn of that entry works.
-- Group rule: if the clicker is the group LEADER, every real (non-bot) member is teleported with them; otherwise only the clicker.
-- Bots are never teleported by this script (playerbots follow their master on their own).
-- Fixed from the old script: leftover debug print, hard-coded Ragefire teleport for groups, hard-coded DB guid.
-- ============================================================
local Settings = require("acore_settings")
local NPC_ENTRY = (Settings.dungeonTeleporter and Settings.dungeonTeleporter.npc) or 0
if NPC_ENTRY == 0 then return true end

math.randomseed(os.time())

-- Every entry is {name, mapId, x, y, z, orientation}.
-- mapId is the CONTINENT the entrance sits on (0 = Eastern Kingdoms,
-- 1 = Kalimdor, 530 = Outland, 571 = Northrend), NOT the dungeon's own
-- map id. The coordinates are the spots the game puts you when you walk
-- OUT of the instance, i.e. right outside the door.
-- Gossip menus hold at most 32 items, so keep each list to ~30 entries.
-- ============================================================




-- ============================================================
-- Dungeons
-- ============================================================

local CLASSIC_DUNGEONS = {
    {"Ragefire Chasm",                        1,  1814.99,   -4419.23,  -18.8151, 1.91986},
    {"The Deadmines",                         0, -11208.7,    1675.9,    24.5733, 4.71239},
    {"Wailing Caverns",                       1,   -740.059, -2214.23,   16.1374, 5.68},
    {"Shadowfang Keep",                       0,   -233.011,  1567.5,    76.8921, 4.27606},
    {"The Stockade",                          0,  -8766.11,    845.499,  87.9952, 3.83972},
    {"Blackfathom Deeps",                     1,   4247.74,    745.879, -24.5299, 4.5828},  -- underwater entrance
    {"Razorfen Kraul",                        1,  -4463.32,  -1664.29,   82.2436, 3.92699},
    {"Gnomeregan",                            0,  -5163.33,    927.623, 257.188,  0},
    {"Uldaman",                               0,  -6066.25,  -2954.56,  209.772,  3.14159},
    {"Razorfen Downs",                        1,  -4658.12,  -2526.35,   81.492,  1.25978},
    {"Scarlet Monastery - Graveyard",         0,   2915.34,   -801.58,  160.333,  3.49066},
    {"Scarlet Monastery - Library",           0,   2869.32,   -820.818, 160.333,  0.349066},
    {"Scarlet Monastery - Armory",            0,   2885.96,   -835.802, 160.327,  0.349066},
    {"Scarlet Monastery - Cathedral",         0,   2915.13,   -823.637, 160.327,  3.49066},
    {"Zul'Farrak",                            1,  -6795.56,  -2890.72,    8.88742, 3.14159},
    {"Maraudon - Foulspore Cavern (Purple)",  1,  -1182.8,    2877.43,   85.908,  1.65806},
    {"Maraudon - Wicked Grotto (Orange)",     1,  -1468.2,    2614.21,   76.3804, 0},
    {"Sunken Temple",                         0, -10176.6,   -3995.35, -112.185,  3.00197},
    {"Blackrock Depths",                      0,  -7178.41,   -922.152, 166.092,  2.00713},
    {"Blackrock Spire (Lower/Upper)",         0,  -7524.7,   -1228.41,  285.733,  1.74533},
    {"Scholomance",                           0,   1273.91,  -2553.09,   90.6322, 3.57793},
    {"Stratholme - Main Gate",                0,   3352.92,  -3379.03,  144.782,  6.25},     -- verify with .gps
    {"Stratholme - Service Entrance",         0,   3233.06,  -4048.3,   108.442,  2.00713},
    {"Dire Maul - East",                      1,  -4031.25,    129.345,  26.4744, 1.5708},   -- verify with .gps
    {"Dire Maul - North",                     1,  -3520.65,   1077.72,  161.138,  1.5009},   -- verify with .gps
    {"Dire Maul - West",                      1,  -3747.96,   1249.18,  160.217,  3.15827},  -- verify with .gps
}

local TBC_DUNGEONS = {
    {"Hellfire Ramparts",         530,  -360.671,  3071.9,   -15.0977, 5.14274},
    {"The Blood Furnace",         530,  -303.506,  3164.82,   31.7425, 5.24025},
    {"The Shattered Halls",       530,  -311.16,   3082.1,    -3.71,   4.92},
    {"The Slave Pens",            530,   719.508,  6999.34,  -73.0743, 4.52702},
    {"The Underbog",              530,   777.089,  6763.45,  -72.0662, 2.72453},
    {"The Steamvault",            530,   816.59,   6934.67,  -80.5446, 4.53174},
    {"Mana-Tombs",                530, -3079.81,   4943.04, -101.047,  3.16432},
    {"Sethekk Halls",             530, -3361.96,   4660.41, -101.048,  4.76654},
    {"Auchenai Crypts",           530, -3362.22,   5225.77, -101.049,  1.62101},
    {"Shadow Labyrinth",          530, -3645.06,   4943.62, -101.048,  6.27058},
    {"Old Hillsbrad Foothills",     1, -8334.98,  -4055.32, -207.737,  3.27431},
    {"The Black Morass",            1, -8765.66,  -4175,    -209.863,  5.53463},
    {"The Mechanar",              530,  3312.09,   1331.89,  505.559,  2.00554},
    {"The Botanica",              530,  3413.65,   1483.32,  182.838,  2.54432},
    {"The Arcatraz",              530,  2862.41,   1546.09,  252.161,  0.805457},
    {"Magisters' Terrace",        530, 12884.6,   -7336.17,   65.48,   1.09},
}

local WOTLK_DUNGEONS = {
    {"Utgarde Keep",              571,  1228.09,  -4862.45,   41.248,  3.443},
    {"Utgarde Pinnacle",          571,  1237.2,   -4859.27,  218.283,  0.274},
    {"The Nexus",                 571,  3897.42,   6985.33,   69.487,  3.17},
    {"The Oculus",                571,  3876.16,   6984.44,  106.32,   6.279},
    {"Azjol-Nerub",               571,  3678.05,   2166.4,    35.795,  5.58},
    {"Ahn'kahet: The Old Kingdom",571,  3641.84,   2032.94,    2.47,   1.178},
    {"Drak'Tharon Keep",          571,  4774.47,  -2028.04,  229.373,  4.645},
    {"The Violet Hold",           571,  5680.7,     487.323, 652.418,  0.882},
    {"Gundrak",                   571,  6702.47,  -4660.55,  441.568,  0.75},
    {"Halls of Stone",            571,  8921.93,   -970.399,1039.2,    4.726},
    {"Halls of Lightning",        571,  9182.91,  -1384.73, 1110.21,   2.431},
    {"The Culling of Stratholme",   1, -8756.87,  -4459.29, -200.73,   1.32},
    {"Trial of the Champion",     571,  8577.4,     791.732, 558.235,  0},
    {"The Forge of Souls",        571,  5667.72,   2007.19,  798.042,  2.31535},
    {"Pit of Saron",              571,  5595.92,   2013.02,  798.041,  0.648728},
    {"Halls of Reflection",       571,  5630.59,   1997.55,  798.049,  1.44042},
}


-- ============================================================
-- Raids (attunements / raid-group rules still apply at the door)
-- ============================================================

local CLASSIC_RAIDS = {
    {"Onyxia's Lair",             1,  -4750.38,  -3754.44,   49.0485, 0.785398},
    {"Naxxramas (Classic 40-man)", 0,  3123.26,  -3869.36,  139.34,   0.2175},    -- Individual Progression teleporter, Eastern Plaguelands
    {"Molten Core",               0,  -7506.95,  -1040.91,  180.91,   3.35},
    -- BWL: next to the Upper Blackrock Spire summoning stone (world.gameobject guid 428), outside the instance
    {"Blackwing Lair",            0,  -7625.35,  -1226.51,  232.78,   -2.77262},
    {"Zul'Gurub",                 0, -11916.3,   -1208.37,   92.2868, 1.61792},
    {"Ruins of Ahn'Qiraj",        1,  -8418.5,    1505.94,   31.8232, 0},
    {"Temple of Ahn'Qiraj",       1,  -8239.01,   1993.25,  129.071,  4.01426},
}

local TBC_RAIDS = {
    {"Karazhan",                  0, -11112.9,   -2005.89,   49.3307, 4.02516},
    {"Gruul's Lair",            530,   3549.8,    5085.97,    2.46332, 2.25742},
    {"Magtheridon's Lair",      530,   -313.679,  3088.35, -116.502,  2.05307},
    {"Serpentshrine Cavern",    530,    827.011,  6865.47,  -63.7844, 3.06507},
    {"Tempest Keep",            530,   3087.31,   1373.79,  184.643,  1.52918},
    {"Hyjal Summit",              1,  -8177.5,   -4183,    -168,      4.5},
    {"Black Temple",            530,  -3653.51,    317.493,  36.1671, 6.24941},
    {"Zul'Aman",                530,   6851.5,   -7997.68,  192.36,   1.56688},
    {"Sunwell Plateau",         530,  12560.8,   -6774.59,   15.08,   6.25},
}

local WOTLK_RAIDS = {
    {"Naxxramas (Wrath 10/25)",  571,   3669.73,  -1269.68,  244.61,   2.40448},   -- summoning stone on the Dragonblight platform
    {"The Obsidian Sanctum",    571,   3448,       261.545, -110.163, 0.097},
    {"Vault of Archavon",       571,   5480.88,   2840.47,  418.68,   3.14},
    {"Ulduar",                  571,   9345.56,  -1114.88, 1245.09,   3.11},
    {"Trial of the Crusader",   571,   8515.46,    728.92,  558.3,    4.742},
    {"Icecrown Citadel",        571,   5790,      2071.48,  636.065,  0.459897},
    {"The Ruby Sanctum",        571,   3604.23,    192.083, -110.821, 2.195},
}

-- ============================================================
-- Menu layout. intid: 100*i = open category i, 100*i+1 = random in category i,
-- 1000*i+n = entry n of category i, 700 = random dungeon, 999 = back
-- ============================================================
local CATEGORIES = {
    {name = "Classic Dungeons",                list = CLASSIC_DUNGEONS},
    {name = "The Burning Crusade Dungeons",    list = TBC_DUNGEONS},
    {name = "Wrath of the Lich King Dungeons", list = WOTLK_DUNGEONS},
    {name = "Classic Raids",                   list = CLASSIC_RAIDS},
    {name = "The Burning Crusade Raids",       list = TBC_RAIDS},
    {name = "Wrath of the Lich King Raids",    list = WOTLK_RAIDS},
}
local ID_RANDOM_DUNGEON, ID_BACK = 700, 999

local ALL_DUNGEONS = {}
for _, list in ipairs({CLASSIC_DUNGEONS, TBC_DUNGEONS, WOTLK_DUNGEONS}) do
    for _, d in ipairs(list) do ALL_DUNGEONS[#ALL_DUNGEONS + 1] = d end
end

local function PickRandom(list) return list[math.random(1, #list)] end

local function Teleport(player, dest)
    if not dest then return end
    player:GossipComplete()
    local group = player:GetGroup()
    if group and group:IsLeader(player:GetGUID()) then
        for _, member in pairs(group:GetMembers()) do
            if member and not member:IsBot() then member:Teleport(dest[2], dest[3], dest[4], dest[5], dest[6]) end
        end
    else
        player:Teleport(dest[2], dest[3], dest[4], dest[5], dest[6])
    end
end

local function ShowMain(player, creature)
    player:GossipClearMenu()
    for i, cat in ipairs(CATEGORIES) do player:GossipMenuAddItem(0, cat.name, 0, i * 100, false) end
    player:GossipMenuAddItem(0, "Random Dungeon", 0, ID_RANDOM_DUNGEON, false)
    player:GossipSendMenu(1, creature)
end

local function ShowCategory(player, creature, catIndex)
    local cat = CATEGORIES[catIndex]
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "== Random: " .. cat.name .. " ==", 0, catIndex * 100 + 1, false)
    for n, entry in ipairs(cat.list) do player:GossipMenuAddItem(0, entry[1], 0, catIndex * 1000 + n, false) end
    player:GossipMenuAddItem(0, "<-- Back", 0, ID_BACK, false)
    player:GossipSendMenu(1, creature)
end

local function OnHello(event, player, creature)
    ShowMain(player, creature)
    return true
end

local function OnSelect(event, player, creature, sender, intid)
    if intid == ID_BACK then
        ShowMain(player, creature)
    elseif intid == ID_RANDOM_DUNGEON then
        Teleport(player, PickRandom(ALL_DUNGEONS))
    elseif intid < 700 then
        local catIndex = math.floor(intid / 100)
        local cat = CATEGORIES[catIndex]
        if cat then
            if intid % 100 == 0 then ShowCategory(player, creature, catIndex)
            elseif intid % 100 == 1 then Teleport(player, PickRandom(cat.list)) end
        end
    elseif intid >= 1000 then
        local cat = CATEGORIES[math.floor(intid / 1000)]
        if cat then Teleport(player, cat.list[intid % 1000]) end
    end
    return true
end

RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnSelect)
print("[dungeon teleporter] enabled on creature entry " .. NPC_ENTRY)
return true

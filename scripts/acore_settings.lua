-- ============================================================
-- SERVER OWNER SETTINGS (edit freely; installer/updater never overwrites this file once it exists).
-- Apply: restart the server, or console: reload ale
-- ============================================================
return {
    shop = {
        currency = "item",      -- "item" = pay with an item (shop.item), "gold" = pay with gold
        item     = 19182,       -- item id used when currency = "item" (19182 = Darkmoon Faire Prize Ticket)
        -- Item mode: pet/mount prices come from the generated catalog (pets 50, mounts 100, toys per list);
        --            services cost serviceItemCost of the item (0 = free).
        serviceItemCost = 0,
        -- Gold mode: gold per purchase.
        gold = { pet = 100, mount = 500, toy = 100, service = 0 },
    },
    -- Item given as an extra reward for dungeon/raid boss kills. false (or 0) = no extra item.
    rewards = {
        item = 19182,
        resetHearthstoneOnDungeonExit = true,   -- free hearthstone use after leaving a dungeon/raid
    },
    -- Dungeon teleporter NPC (creature_template entry). 0 = disabled.
    -- Entry 900001 = generic "Chromie" (no quests), created by custom-sql/001_chromie_teleporter_npc.sql.
    -- TO PLACE HER (GM, in game): stand where you want her and type   .npc add 900001
    --   (saved permanently; move with .npc move, remove by targeting her and typing .npc delete; face her with .npc set o)
    -- Then: restart the server or console `reload ale`.
    dungeonTeleporter = { npc = 900001 },
    -- Garrisons (housing): players pick one of the locations in scripts/garrison.lua at the portal (Stormwind Mage Tower or Orgrimmar).
    garrison = { enabled = true, debug = false,
                 -- price of claiming a garrison at the portal (every pick, also when switching; abandoning refunds nothing). currency = "free" | "gold" | "item"; amount = gold or item count; item = item id
                 cost = { currency = "free", item = 0, amount = 0 },
                 -- perks inside a garrison: instantLogout = /logout is instant (like an inn); rested = rested XP builds up (restedRate 1.0 = the core's inn speed)
                 perks = { instantLogout = true, rested = true, restedRate = 1.0 },
                 maxPets = 5, markerSeconds = 30,
                 maxDecor = 1000,    -- most decor pieces one garrison can hold (shown in the garrison window as placed/max). Every piece is a spawned object: very high values cost server and client performance
                 currency = "free", currencyItem = 0 },   -- currency = "free" | "gold" | "item"; currencyItem = item id paid in when currency = "item". Prices come from the catalog (category default + per-item override, set in the admin tool)   -- maxPets = companions roaming at once   -- debug = true adds [garrison:debug] lines to the server log
}

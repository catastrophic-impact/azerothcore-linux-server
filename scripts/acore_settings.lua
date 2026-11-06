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
    -- Garrisons (housing). Proof of concept: one location (Northshire Abbey), every account gets a garrison automatically.
    garrison = { enabled = true, debug = false, maxPets = 5, markerSeconds = 30,
                 currency = "free", currencyItem = 0 },   -- currency = "free" | "gold" | "item"; currencyItem = item id paid in when currency = "item". Prices come from the catalog (category default + per-item override, set in the admin tool)   -- maxPets = companions roaming at once   -- debug = true adds [garrison:debug] lines to the server log
}

-- ============================================================
-- Garrison (housing) - phased player garrisons.
-- * The portal (gameobject 900002, Stormwind Mage Tower = .tele garportal) lets a player pick one garrison LOCATION (world table garrison_location),
--   enter it, or abandon it (everything placed is lost). Locations are plain data: .garrison addloc <name> adds one without touching code.
-- * Inside, the player has their own phase bit (the normal world is hidden, only our spawns exist). Leaving the area asks Leave / Stay.
-- * Layout and decor are stored per ACCOUNT in the characters database (all SQL is in garrison_store.lua) and spawned (NOT saved to the world DB)
--   when the first occupant arrives, despawned when the last leaves.
-- * Bots are never inside.
--
-- This file only wires the parts together. Each part is a file  garrison_<name>.lua  that returns function(G); G is the table they share.
-- Parts talk through G (functions/data) and through the hooks below: a part never edits another one.
--   hooks: G.OnEnter(fn(player, h, owner))   after the player was phased + teleported in
--          G.OnLeave(fn(guidLow, player, h, reason))   player may be nil (offline); reason: nil|"logout"|"away"|"phase"|"abandon"|"purge"|"error"
--          G.OnClose(fn(h, owner))   the last occupant left, the garrison is about to be despawned
--          G.OnTick(fn(player, h, now))   once a second per occupant that is inside the area
--          G.OnLogin(fn(player, wasInsideGarrison))     G.OnStray(fn(player))   found in a garrison phase without being inside (after a reload)
-- ============================================================
local Settings = require("acore_settings")
if Settings.garrison and Settings.garrison.enabled == false then return true end

local G = { Msg = require("acore_msg"), Settings = Settings, active = {}, inside = {}, Menagerie = {} }
-- active: ownerAccount -> open garrison h = { bit, loc, occ = {guidLow = ObjectGuid}, n, spawned, pets, rows, decor }; inside: player guidLow -> ownerAccount.
-- Everything is keyed by GUID/account; never hold Player objects across ticks.

local hooks = { enter = {}, leave = {}, close = {}, tick = {}, login = {}, stray = {} }
function G.Fire(name, ...)
    for _, fn in ipairs(hooks[name]) do
        local ok, err = pcall(fn, ...)
        if not ok then print("[garrison] " .. name .. " hook error: " .. tostring(err)) end
    end
end
for name, key in pairs({ OnEnter = "enter", OnLeave = "leave", OnClose = "close", OnTick = "tick", OnLogin = "login", OnStray = "stray" }) do
    G[name] = function(fn) table.insert(hooks[key], fn) end
end

-- install order matters: a part may only use what the parts before it exported. Optional parts belong to another component (the jukebox
-- component ships garrison_jukebox.lua): if their file is not there they are skipped.
local PARTS = { "config", "items", "curate", "economy", "store", "locations", "spawn", "session", "portal", "placement", "ghost", "menagerie", "wildlife", "props", { "jukebox", optional = true }, "perks", "gm" }
for _, part in ipairs(PARTS) do
    local name = type(part) == "table" and part[1] or part
    local ok, mod = pcall(require, "garrison_" .. name)
    if not ok and type(part) == "table" and part.optional and tostring(mod):find("not found", 1, true) then
        print("[garrison] optional part '" .. name .. "' is not installed, skipping")
    else
        local ok2, err = ok and pcall(mod, G)
        if not ok or not ok2 then
            print("[garrison] FAILED to install part '" .. name .. "': " .. tostring(ok and err or mod) .. " - the garrison system is not usable until this is fixed")
            return false
        end
    end
end
if rawget(_G, "GARRISON_TEST") then ACORE_G = G end   -- the test harness (tools/test_garrison.lua) reads the shared table
G.HealStrays()
local bits = {}
for _, l in ipairs(G.locations.List()) do bits[#bits + 1] = l.name .. " " .. #G.locations.FreeBits(l.map) end
print(string.format("[garrison] loaded (%d placeable kinds, %d locations; phase bits: %s)", #G.CATALOG, #G.locations.List(), table.concat(bits, ", ")))
return true

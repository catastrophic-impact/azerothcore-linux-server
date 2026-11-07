-- Garrison module 1/14: settings. Every setting the garrison reads comes from here (acore_settings.lua -> garrison), with its default.
-- Modules are installed by garrison.lua: each file returns function(G); G is the shared table the modules use to find each other.
return function(G)
    local S = (G.Settings and G.Settings.garrison) or {}
    local cost, perks = S.cost or {}, S.perks or {}
    local C = {
        debug = S.debug and true or false,
        maxDecor = S.maxDecor or 100,            -- all decor in one garrison
        maxPerKind = S.maxPerKind or 10,         -- of the same decor item
        maxPets = S.maxPets or 5,                -- pets out at once
        markerNpc = S.markerNpc or 900010,       -- custom-sql/007: "Garrison Marker"
        markerSpell = S.markerSpell or 1130,     -- Hunter's Mark
        markerSeconds = S.markerSeconds or 30,
        currency = S.currency or "free",         -- price of placing things: "free" | "gold" | "item"
        currencyItem = S.currencyItem or 0,
        portalEntry = 900002,                    -- the portal gameobject (custom-sql/002_garrison.sql)
        -- where the portal stands and where players are sent when they leave a garrison (Stormwind, Mage Tower = .tele garportal)
        hub = S.hub or { map = 0, x = -8981.65, y = 855.01, z = 29.621, o = 3.03693 },
        arriveDist = 20,                         -- yards from the portal point towards the center where you appear
        arriveGrace = 10,                        -- seconds the area check ignores a player whose teleport has not landed yet
        leaveSeconds = S.leaveSeconds or 5,      -- countdown after you cross the border: walk back in before it ends or you are sent to the Mage Tower
        leaveLimit = S.leaveLimit or 20,         -- ...and how many yards past the border you may get during the countdown before you are sent out at once
        claim = { currency = cost.currency or "free", item = cost.item or 0, amount = cost.amount or 0 },   -- price of claiming a garrison
        perks = {                                -- inside a garrison: instant /logout (like an inn) and rested XP
            instantLogout = perks.instantLogout ~= false,
            rested = perks.rested ~= false,
            restedRate = perks.restedRate or 1.0,   -- 1.0 = the same speed as the core's inn rate
        },
    }
    if C.currency == "item" and C.currencyItem == 0 then print("[garrison] currency = item but currencyItem is 0: treating as free"); C.currency = "free" end
    local c = C.claim
    if c.currency == "item" and c.item == 0 then print("[garrison] cost.currency = item but cost.item is 0: treating as free"); c.currency = "free" end
    if c.currency == "free" or c.amount <= 0 then c.currency, c.amount = "free", 0 end
    G.cfg = C
    G.dbg = function(...) if C.debug then print("[garrison:debug] " .. table.concat({ ... }, " ")) end end
    G.Say = function(player, text) player:SendBroadcastMessage("|cff66ccffGarrison:|r " .. text) end
end

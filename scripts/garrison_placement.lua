-- Garrison module 9/14: placing things in YOUR garrison (client addon wotlk_garrison): single-instance buildings/NPCs ("place"/"remove") and
-- decor with many instances ("dplace"/"dmove"/"dremove"/"dclear"). Every change is written through garrison_store.lua and then respawned.
return function(G)
    local Msg, store, cfg, Say = G.Msg, G.store, G.cfg, G.Say
    local Loc, BY_KIND, MyHouse = G.locations.Get, G.BY_KIND, G.MyHouse
    local SpawnOne, DespawnKind, Charge, Refund, Money, CanPlace = G.SpawnOne, G.DespawnKind, G.Charge, G.Refund, G.Money, G.CanPlace
    local MAX_DECOR, MAX_PER_KIND = cfg.maxDecor, cfg.maxPerKind
    local function Res(player, text) Msg.Send(player, "house", "res", text) end

    -- ---- helpers other modules use too ----
    local function CountDecor(h, kind)
        local total, ofKind = 0, 0
        for _, r in pairs(h.decor) do total = total + 1; if r.kind == kind then ofKind = ofKind + 1 end end
        return total, ofKind
    end
    local function GroundZ(loc, x, y, z)   -- snap to terrain unless that would jump onto a roof / under a floor (>3 yards away)
        local map = GetMapById(loc.map, 0)
        local gz = map and map:GetHeight(x, y, 1)
        if gz and math.abs(gz - z) <= 3 then return gz end
        return z
    end
    local function InsideArea(loc, x, y) return G.locations.Inside(loc, x, y) end
    -- limits for one more decor item; returns nil when fine, else the message
    local function DecorLimit(h, kind)
        local total, ofKind = CountDecor(h, kind)
        if total >= MAX_DECOR then return "Garrison decor limit reached (" .. MAX_DECOR .. ")." end
        if ofKind >= MAX_PER_KIND then return "You already have " .. MAX_PER_KIND .. " of those." end
    end
    -- shared by "dplace" (instant, 3 yards ahead) and placement mode ("pconfirm"): limits, price, row, spawn. Returns true when placed.
    local function PlaceDecorAt(player, h, owner, kind, def, x, y, z, o)
        local why = DecorLimit(h, kind)
        if why then Res(player, why); return false end
        local ok, paid, pcur, fail = Charge(player, def)
        if not ok then Res(player, fail); return false end
        local row = { did = store.NextDecorId(), kind = kind, x = x, y = y, z = z, o = o, paid = paid, pcur = pcur }
        store.InsertDecor(owner, h.loc, row)
        SpawnOne(h, row)
        Msg.Send(player, "house", "dnew", tostring(row.did))
        local total = CountDecor(h, kind)
        Res(player, "Placed: " .. def.name .. " (" .. total .. "/" .. MAX_DECOR .. ")" .. (paid > 0 and (" - paid " .. Money(paid, pcur)) or ""))
        return true
    end
    G.CountDecor, G.GroundZ, G.InsideArea, G.DecorLimit, G.PlaceDecorAt = CountDecor, GroundZ, InsideArea, DecorLimit, PlaceDecorAt

    -- ---- protocol ----
    Msg.On("house", "adm", function(player)   -- the client asks before opening /garrison admin: GM level 3 and up
        Msg.Send(player, "house", player:GetGMRank() >= 3 and "admok" or "admno", "")
    end)

    Msg.On("house", "list", function(player)
        -- the client has the static catalog; we only tell it whether you are home and which kinds are placed (chunked: ~240 char limit)
        local h = MyHouse(player)
        Msg.Send(player, "house", "head", h and "1" or "0")
        Msg.Send(player, "house", "cur", cfg.currency .. "," .. cfg.currencyItem)
        if not h then return end
        local chunk, dchunk = "", ""
        for _, sp in ipairs(h.spawned) do
            if sp.did then
                local item = sp.did .. ":" .. sp.kind
                if #dchunk + #item + 1 > 200 then Msg.Send(player, "house", "dplaced", dchunk); dchunk = "" end
                dchunk = dchunk .. (dchunk == "" and "" or ",") .. item
            else
                if #chunk + #sp.kind + 1 > 200 then Msg.Send(player, "house", "placed", chunk); chunk = "" end
                chunk = chunk .. (chunk == "" and "" or ",") .. sp.kind
            end
        end
        if chunk ~= "" then Msg.Send(player, "house", "placed", chunk) end
        if dchunk ~= "" then Msg.Send(player, "house", "dplaced", dchunk) end
    end)

    Msg.On("house", "place", function(player, kind)
        local h, owner = MyHouse(player)
        if not h then return Res(player, "You must be inside your own garrison to place things.") end
        local def = BY_KIND[kind]
        if not def then return Res(player, "Unknown item.") end
        if def.multi then return Res(player, "Use 'Place new' for decor.") end
        local row = { kind = kind, x = player:GetX(), y = player:GetY(), z = player:GetZ(), o = player:GetO(), paid = 0, pcur = "" }
        local old = h.rows[kind]
        if old then row.paid, row.pcur = old.paid or 0, old.pcur or ""    -- placing again = moving: free, keeps what was paid
        else
            local ok, paid, pcur, why = Charge(player, def)
            if not ok then return Res(player, why) end
            row.paid, row.pcur = paid, pcur
        end
        DespawnKind(h, kind)    -- one of each kind: placing again moves it
        store.SaveObject(owner, h.loc, row)
        SpawnOne(h, row)
        if kind == "menagerie" then G.Menagerie.Roll(h, owner, player:GetGUIDLow()) end
        Res(player, (old and "Moved: " or "Placed: ") .. def.name .. (row.paid > 0 and not old and (" (paid " .. Money(row.paid, row.pcur) .. ")") or ""))
    end)

    Msg.On("house", "remove", function(player, kind)
        local h, owner = MyHouse(player)
        if not h or not BY_KIND[kind] then return end
        local old = h.rows[kind]
        DespawnKind(h, kind)
        if kind == "menagerie" then G.Menagerie.Clear(h); h.rows["menagerie"] = nil end
        store.DeleteObject(owner, h.loc, kind)
        Res(player, "Removed: " .. BY_KIND[kind].name .. (old and Refund(player, old) or ""))
    end)

    Msg.On("house", "dplace", function(player, kind)
        local h, owner = MyHouse(player)
        if not h then return Res(player, "You must be inside your own garrison to place things.") end
        local def = BY_KIND[kind]
        if not CanPlace(player, def) then return Res(player, "Unknown decor item.") end
        local loc, o = Loc(h.loc), player:GetO()
        local x, y = player:GetX() + math.cos(o) * 3, player:GetY() + math.sin(o) * 3
        if not InsideArea(loc, x, y) then x, y = player:GetX(), player:GetY() end
        PlaceDecorAt(player, h, owner, kind, def, x, y, GroundZ(loc, x, y, player:GetZ()), (o + math.pi) % (2 * math.pi))
    end)

    -- payload "<id>,<action>,<amount>": f/b/l/r move relative to the way YOU face, u/d height, rl/rr rotate (degrees), me = move to your spot
    Msg.On("house", "dmove", function(player, payload)
        local h, owner = MyHouse(player)
        if not h then return end
        local id, act, amt = payload:match("^([%w_]+),(%a+),([%d%.]+)$")
        local did = id and id:match("^%d+$") and tonumber(id)          -- digits = decor instance, anything else = a single-instance kind
        local row = id and (did and h.decor[did] or (not did and BY_KIND[id] and h.rows[id]))
        if not row then return Res(player, "That item is gone.") end
        amt = math.max(0.05, math.min(tonumber(amt) or 1, (act == "rl" or act == "rr") and 180 or 30))
        local o, x, y, z, ro = player:GetO(), row.x, row.y, row.z, row.o
        if act == "f" then x, y = x + math.cos(o) * amt, y + math.sin(o) * amt
        elseif act == "b" then x, y = x - math.cos(o) * amt, y - math.sin(o) * amt
        elseif act == "l" then x, y = x + math.cos(o + math.pi / 2) * amt, y + math.sin(o + math.pi / 2) * amt
        elseif act == "r" then x, y = x + math.cos(o - math.pi / 2) * amt, y + math.sin(o - math.pi / 2) * amt
        elseif act == "u" then z = z + amt
        elseif act == "d" then z = z - amt
        elseif act == "rl" then ro = (ro + math.rad(amt)) % (2 * math.pi)
        elseif act == "rr" then ro = (ro - math.rad(amt)) % (2 * math.pi)
        elseif act == "me" then x, y, z = player:GetX(), player:GetY(), player:GetZ()
        elseif act == "snap" then z = GroundZ(Loc(h.loc), x, y, z)
        else return end
        if not InsideArea(Loc(h.loc), x, y) then return Res(player, "That is outside the garrison.") end
        row.x, row.y, row.z, row.o = x, y, z, ro
        if did then
            store.MoveDecor(owner, did, row)
            DespawnKind(h, nil, did)
        else
            store.MoveObject(owner, h.loc, id, row)
            DespawnKind(h, id)
        end
        SpawnOne(h, row)
        if id == "menagerie" then G.Menagerie.Roll(h, owner, player:GetGUIDLow()) end
    end)

    Msg.On("house", "dremove", function(player, did)
        local h, owner = MyHouse(player)
        did = tonumber(did)
        local row = h and did and h.decor[did]
        if not row then return end
        DespawnKind(h, nil, did)
        h.decor[did] = nil
        store.DeleteDecor(owner, did)
        Res(player, "Removed: " .. BY_KIND[row.kind].name .. Refund(player, row))
    end)

    Msg.On("house", "dclear", function(player)
        local h, owner = MyHouse(player)
        if not h then return end
        local n, back = 0, {}
        for did, r in pairs(h.decor) do
            DespawnKind(h, nil, did); n = n + 1
            if (r.paid or 0) > 0 then back[r.pcur] = (back[r.pcur] or 0) + r.paid end
        end
        -- sweep: any decor object still tracked (e.g. its row was lost or its kind is no longer in the catalog)
        local left = {}
        for _, s in ipairs(h.spawned) do if s.did then left[#left + 1] = s.did end end
        for _, did in ipairs(left) do DespawnKind(h, nil, did) end
        h.decor = {}
        local refunded = ""
        for pcur, paid in pairs(back) do refunded = refunded .. Refund(player, { paid = paid, pcur = pcur }) end
        store.ClearDecor(owner, h.loc)
        Res(player, "Removed all decor (" .. n .. ")." .. refunded)
    end)
end

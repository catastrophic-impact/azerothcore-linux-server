-- Garrison module 2b: curation of the decor catalog from inside the game (GM level 3+, "Curator mode" in the garrison window).
-- The generated catalog (garrison_catalog.lua) is the BASE. A curator changes, live and for every player: an item's category / name / price, the
-- preview view of a model, and the category list (add / rename / delete / order / default price). Nothing here edits a file: the changes live in three
-- characters-DB tables and are exported into the repo files with tools/export_curation.py (then tools/gen_garrison_catalog.py folds them into the base).
--   effective category = override, else base.  hid (players cannot place it) = category Removed or Unsorted.
--   effective price    = item override, else the item's generated item-level price (ip), else its category's price, else free.
-- Protocol (module "house"): client -> server  ciset|kind~cat~name~price   cfset|model~vs~vy~vz~vr   cfclr|model   curget
--                                              ccadd|name   ccren|old~new   ccdel|name   ccprice|name~amount
--                            server -> client  curgm|0/1   currev|N   curd|N;<record>   curfull|i/n;<records>   curbad|   (a client behind the revision asks curget)
-- records:  i~kind~cat~name~price (empty field = not overridden)   f~model~vs~vy~vz~vr   k (the category list below is custom)   c~name~price   r~rev
return function(G)
    local Msg, BY_KIND = G.Msg, G.BY_KIND
    local BASE = require("garrison_catalog")
    local S = { item = {}, fit = {}, cats = nil, rev = 0 }   -- cats = ordered { {name=, price=} } once the curator edited the list, else nil (= the base list)
    G.curate = S
    local PINNED = { "Unsorted", "Removed" }   -- always last, never renamed / deleted / moved

    local function Q(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "''") .. "'" end
    local function N(v) return math.floor(tonumber(v) or 0) end
    local function F(v) return string.format("%.4f", tonumber(v) or 0) end
    local function exec(sql) CharDBExecute(sql) end
    local function clean(s, max) return (tostring(s or ""):gsub("[~;|%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, max or 60)) end

    -- ---- base values, effective values ----
    local baseCats, basePrice = {}, {}
    for _, c in ipairs(BASE.cats or {}) do baseCats[#baseCats + 1] = c[1]; basePrice[c[1]] = c[2] end
    for _, c in ipairs(BASE.items) do
        if c.obj then c.basecat = c.cat end
        c.basename = c.name
    end
    local function CatList()   -- names, in order
        if not S.cats then return baseCats end
        local t = {}; for _, c in ipairs(S.cats) do t[#t + 1] = c.name end
        return t
    end
    local function CatPrice(name)
        if S.cats then for _, c in ipairs(S.cats) do if c.name == name then return c.price end end; return nil end
        return basePrice[name]
    end
    local function IsCat(name) for _, n in ipairs(CatList()) do if n == name then return true end end; return false end
    local function IsPinned(name) return name == PINNED[1] or name == PINNED[2] end
    -- categories are always alphabetical (case-insensitive); a subcategory ("Parent > Child") follows its parent, also alphabetical; Unsorted, Removed last
    local function SortKey(n)
        local rank = n == "Removed" and 2 or (n == "Unsorted" and 1 or 0)
        local p, c = n:match("^(.-) > (.+)$")
        return rank, (p or n):lower(), p and c:lower() or ""
    end
    local function SortCats(list)
        table.sort(list, function(a, b)
            local ra, pa, ca = SortKey(a.name); local rb, pb, cb = SortKey(b.name)
            if ra ~= rb then return ra < rb end
            if pa ~= pb then return pa < pb end
            return ca < cb
        end)
    end

    -- recompute what the rest of the garrison reads (def.hid / def.price / def.name) for one catalog entry
    local function Apply(def)
        if not def or not def.obj then return end
        local o = S.item[def.kind]
        local cat = (o and o.cat) or def.basecat
        def.cat = cat
        def.name = (o and o.name) or def.basename
        def.hid = (cat == "Removed" or cat == "Unsorted") or nil
        local p = (o and o.price) or def.ip or CatPrice(cat) or 0
        def.price = p > 0 and p or nil
    end
    local function ApplyAll() for _, def in ipairs(BASE.items) do Apply(def) end end

    -- ---- persistence ----
    function S.Init()
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_cur_item (kind VARCHAR(40) NOT NULL, cat VARCHAR(80) NOT NULL DEFAULT '', name VARCHAR(80) NOT NULL DEFAULT '', price INT NOT NULL DEFAULT -1, PRIMARY KEY (kind)) ENGINE=InnoDB")
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_cur_fit (model VARCHAR(190) NOT NULL, vs DOUBLE NOT NULL, vy DOUBLE NOT NULL, vz DOUBLE NOT NULL, vr DOUBLE NOT NULL, PRIMARY KEY (model)) ENGINE=InnoDB")
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_cur_cat (seq INT NOT NULL, name VARCHAR(80) NOT NULL, price INT NOT NULL DEFAULT 0, PRIMARY KEY (seq)) ENGINE=InnoDB")
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_cur_meta (k VARCHAR(20) NOT NULL, v BIGINT NOT NULL, PRIMARY KEY (k)) ENGINE=InnoDB")
        local q = CharDBQuery("SELECT kind, cat, name, price FROM dc_garrison_cur_item")
        if q then repeat
            local o = { cat = q:GetString(1), name = q:GetString(2), price = tonumber(q:GetString(3)) or -1 }
            S.item[q:GetString(0)] = { cat = o.cat ~= "" and o.cat or nil, name = o.name ~= "" and o.name or nil, price = o.price >= 0 and o.price or nil }
        until not q:NextRow() end
        q = CharDBQuery("SELECT model, vs, vy, vz, vr FROM dc_garrison_cur_fit")
        if q then repeat S.fit[q:GetString(0)] = { q:GetFloat(1), q:GetFloat(2), q:GetFloat(3), q:GetFloat(4) } until not q:NextRow() end
        q = CharDBQuery("SELECT name, price FROM dc_garrison_cur_cat ORDER BY seq")
        if q then S.cats = {}; repeat S.cats[#S.cats + 1] = { name = q:GetString(0), price = q:GetUInt32(1) } until not q:NextRow() end
        q = CharDBQuery("SELECT v FROM dc_garrison_cur_meta WHERE k='rev'")
        S.rev = q and q:GetUInt32(0) or 0
        ApplyAll()
    end
    local function SaveRev() S.rev = S.rev + 1; exec("REPLACE INTO dc_garrison_cur_meta (k, v) VALUES ('rev', " .. S.rev .. ")") end
    local function SaveItem(kind)
        local o = S.item[kind]
        if not o or (not o.cat and not o.name and not o.price) then
            S.item[kind] = nil; exec("DELETE FROM dc_garrison_cur_item WHERE kind=" .. Q(kind))
        else
            exec(string.format("REPLACE INTO dc_garrison_cur_item (kind, cat, name, price) VALUES (%s, %s, %s, %d)", Q(kind), Q(o.cat or ""), Q(o.name or ""), o.price or -1))
        end
    end
    local function SaveCats()
        exec("DELETE FROM dc_garrison_cur_cat")
        for i, c in ipairs(S.cats or {}) do exec(string.format("INSERT INTO dc_garrison_cur_cat (seq, name, price) VALUES (%d, %s, %d)", i, Q(c.name), c.price or 0)) end
    end

    -- ---- wire records ----
    local function ItemRec(kind)
        local o = S.item[kind] or {}
        return "i~" .. kind .. "~" .. (o.cat or "") .. "~" .. (o.name or "") .. "~" .. (o.price or "")
    end
    local function FitRec(model, f) return "f~" .. model .. "~" .. string.format("%.3f~%.3f~%.3f~%.3f", f[1], f[2], f[3], f[4]) end
    local function AllRecords()
        local recs = { "r~" .. S.rev }
        if S.cats then
            recs[#recs + 1] = "k"
            for _, c in ipairs(S.cats) do recs[#recs + 1] = "c~" .. c.name .. "~" .. (c.price or 0) end
        end
        for kind in pairs(S.item) do recs[#recs + 1] = ItemRec(kind) end
        for model, f in pairs(S.fit) do recs[#recs + 1] = FitRec(model, f) end
        return recs
    end
    local function Players(fn)
        for _, p in pairs(GetPlayersInWorld() or {}) do if p and not p:IsBot() then fn(p) end end
    end
    local function SendFullChunks(player)
        local parts, cur = {}, ""
        for _, r in ipairs(AllRecords()) do
            if #cur + #r + 1 > 190 then parts[#parts + 1] = cur; cur = "" end
            cur = cur .. (cur == "" and "" or ";") .. r
        end
        parts[#parts + 1] = cur
        for i, part in ipairs(parts) do Msg.Send(player, "house", "curfull", i .. "/" .. #parts .. ";" .. part) end
    end
    local function Broadcast(action, payload) Players(function(p) Msg.Send(p, "house", action, payload) end) end

    function S.Hello(player)   -- called from the "list" handler before "head": tells the client its curator right and the current revision
        Msg.Send(player, "house", "curgm", player:GetGMRank() >= 3 and "1" or "0")
        Msg.Send(player, "house", "currev", tostring(S.rev))
    end
    Msg.On("house", "curget", function(player) SendFullChunks(player) end)

    -- ---- curator operations (GM level 3 only) ----
    local function Curator(player)
        if player:GetGMRank() >= 3 then return true end
        Msg.Send(player, "house", "curbad", "")
        return false
    end
    local function Reply(player, text) Msg.Send(player, "house", "res", text) end
    local function Split(payload, n)
        local t = {}
        for part in (tostring(payload) .. "~"):gmatch("(.-)~") do t[#t + 1] = part end
        return t
    end
    local function Pub(record) SaveRev(); Broadcast("curd", S.rev .. ";" .. record) end   -- after a small change: bump the revision, tell everyone

    Msg.On("house", "ciset", function(player, payload)
        if not Curator(player) then return end
        local t = Split(payload)
        local def = BY_KIND[t[1] or ""]
        if not def or not def.obj then return Reply(player, "Unknown decor item.") end
        local cat = clean(t[2], 80)
        if cat ~= "" and not IsCat(cat) then return Reply(player, "Unknown category: " .. cat) end
        local name = clean(t[3], 60)
        local price = t[4] and t[4] ~= "" and tonumber(t[4]) or nil
        if price then price = math.max(0, math.min(1000000, math.floor(price))) end
        if cat == def.basecat then cat = "" end   -- equal to the base: no override
        if name == def.basename then name = "" end
        S.item[def.kind] = { cat = cat ~= "" and cat or nil, name = name ~= "" and name or nil, price = price }
        SaveItem(def.kind); Apply(def)
        Pub(ItemRec(def.kind))
    end)

    local function CleanModel(m) return clean(m, 190):lower() end
    Msg.On("house", "cfset", function(player, payload)
        if not Curator(player) then return end
        local t = Split(payload)
        local model = CleanModel(t[1])
        local vs, vy, vz, vr = tonumber(t[2]), tonumber(t[3]), tonumber(t[4]), tonumber(t[5])
        if model == "" or not vs or not vy or not vz or not vr or vs <= 0.01 or vs > 60 or math.abs(vy) > 300 or math.abs(vz) > 300 then return Reply(player, "Bad view values.") end
        vs, vy, vz, vr = math.floor(vs * 1000 + .5) / 1000, math.floor(vy * 1000 + .5) / 1000, math.floor(vz * 1000 + .5) / 1000, math.floor(vr * 1000 + .5) / 1000
        S.fit[model] = { vs, vy, vz, vr }
        exec(string.format("REPLACE INTO dc_garrison_cur_fit (model, vs, vy, vz, vr) VALUES (%s, %s, %s, %s, %s)", Q(model), F(vs), F(vy), F(vz), F(vr)))
        Pub(FitRec(model, S.fit[model]))
    end)
    Msg.On("house", "cfclr", function(player, payload)
        if not Curator(player) then return end
        local model = CleanModel(payload)
        if not S.fit[model] then return end
        S.fit[model] = nil; exec("DELETE FROM dc_garrison_cur_fit WHERE model=" .. Q(model))
        SaveRev(); Broadcast("currev", tostring(S.rev))   -- a cleared fit goes back to the BASE fit, which only the client knows: everyone resyncs
    end)

    -- ---- categories ----
    local function Seed()   -- the first category edit copies the base list into the table
        if S.cats then return end
        S.cats = {}
        for _, n in ipairs(baseCats) do if not IsPinned(n) then S.cats[#S.cats + 1] = { name = n, price = basePrice[n] or 0 } end end
        for _, n in ipairs(PINNED) do S.cats[#S.cats + 1] = { name = n, price = basePrice[n] or 0 } end   -- Unsorted, Removed: always last
        SortCats(S.cats)
    end
    local function Index(name) for i, c in ipairs(S.cats) do if c.name == name then return i end end end
    local function Done(player, text)   -- a category change affects many items: everyone resyncs from the new revision
        SortCats(S.cats); SaveCats(); ApplyAll(); SaveRev(); Broadcast("currev", tostring(S.rev)); if text then Reply(player, text) end
    end
    local function Under(name, parent) return name == parent or name:sub(1, #parent + 3) == parent .. " > " end

    Msg.On("house", "ccadd", function(player, payload)
        if not Curator(player) then return end
        local name = clean(payload, 60)
        if name == "" then return end
        Seed()
        if Index(name) then return Reply(player, "That category already exists.") end
        table.insert(S.cats, { name = name, price = 0 })   -- Done() sorts the list
        Done(player, "Category added: " .. name)
    end)
    Msg.On("house", "ccren", function(player, payload)
        if not Curator(player) then return end
        local t = Split(payload)
        local old, new = clean(t[1], 80), clean(t[2], 60)
        if old == "" or new == "" or old == new then return end
        if IsPinned(old) or IsPinned(new) then return Reply(player, "Unsorted and Removed cannot be renamed.") end
        Seed()
        local any = false
        for _, c in ipairs(S.cats) do if Under(c.name, old) then any = true end end
        if not any then return Reply(player, "Unknown category.") end
        for _, c in ipairs(S.cats) do if Under(c.name, new) and not Under(c.name, old) then return Reply(player, "A category named " .. new .. " already exists.") end end
        local function Re(name) return Under(name, old) and (new .. name:sub(#old + 1)) or name end
        for _, c in ipairs(S.cats) do c.name = Re(c.name) end
        local touched = {}
        for _, def in ipairs(BASE.items) do
            if def.obj then
                local nc = Re(def.cat)
                if nc ~= def.cat then
                    local o = S.item[def.kind] or {}
                    o.cat = (nc ~= def.basecat) and nc or nil
                    S.item[def.kind] = o; touched[def.kind] = true
                end
            end
        end
        for kind in pairs(touched) do SaveItem(kind) end
        Done(player, "Renamed: " .. old .. " -> " .. new)
    end)
    Msg.On("house", "ccdel", function(player, payload)
        if not Curator(player) then return end
        local name = clean(payload, 80)
        if IsPinned(name) then return Reply(player, "Unsorted and Removed cannot be deleted.") end
        Seed()
        local i = Index(name)
        if not i then return Reply(player, "Unknown category.") end
        for _, c in ipairs(S.cats) do if c.name:sub(1, #name + 3) == name .. " > " then return Reply(player, "Delete or move its subcategories first.") end end
        table.remove(S.cats, i)
        local moved, touched = 0, {}
        for _, def in ipairs(BASE.items) do
            if def.obj and def.cat == name then
                local o = S.item[def.kind] or {}
                o.cat = (def.basecat ~= "Unsorted") and "Unsorted" or nil
                S.item[def.kind] = o; touched[def.kind] = true; moved = moved + 1
            end
        end
        for kind in pairs(touched) do SaveItem(kind) end
        Done(player, "Deleted " .. name .. " (" .. moved .. " items moved to Unsorted)")
    end)
    Msg.On("house", "ccprice", function(player, payload)
        if not Curator(player) then return end
        local t = Split(payload)
        local name, amount = clean(t[1], 80), math.max(0, math.min(1000000, math.floor(tonumber(t[2]) or 0)))
        Seed()
        local i = Index(name)
        if not i then return Reply(player, "Unknown category.") end
        S.cats[i].price = amount
        Done(player, name .. ": default price " .. amount)
    end)

    S.Init()
    print(string.format("[garrison] curation loaded (rev %d, %d item override(s), %d view(s), %s)", S.rev, (function() local n = 0; for _ in pairs(S.item) do n = n + 1 end; return n end)(),
        (function() local n = 0; for _ in pairs(S.fit) do n = n + 1 end; return n end)(), S.cats and "custom categories" or "base categories"))
end

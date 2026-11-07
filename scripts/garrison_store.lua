-- Garrison module 4/14: the ONLY place that talks to the characters database (and the one place that reads dc_companion).
-- Rules this layer follows:
--  * player data is keyed by ACCOUNT; nothing here deletes data it was not explicitly asked to delete (no cleanup at load, except
--    garrison rows of accounts that no longer exist, and only after the auth database answered sanely)
--  * schema: the legacy tables (object, decor, setting, logout, spawn) come from custom-sql/002, 004, 006; the tables added later (meta, owner)
--    are created here. Every table has exactly one creator. dc_garrison_meta records which one-time migrations already ran.
--  * deleting a garrison removes the DATA first and the ownership row LAST, so an interrupted delete leaves an empty garrison, never orphaned data
--  * values that go into SQL are numbers (forced with %d / %f) or quoted strings (Q)
return function(G)
    local S = {}
    G.store = S

    local function Q(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "''") .. "'" end
    local function N(v) return math.floor(tonumber(v) or 0) end
    local function exec(sql) CharDBExecute(sql) end

    -- ---- schema + one-time migrations ----
    local function Meta(k)
        local q = CharDBQuery("SELECT v FROM dc_garrison_meta WHERE k=" .. Q(k))
        return q and q:GetString(0) or nil
    end
    local function SetMeta(k, v) exec("REPLACE INTO dc_garrison_meta (k, v) VALUES (" .. Q(k) .. "," .. Q(v) .. ")") end

    function S.Init()
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_meta (k VARCHAR(40) NOT NULL, v VARCHAR(100) NOT NULL, PRIMARY KEY (k)) ENGINE=InnoDB")
        CharDBQuery("CREATE TABLE IF NOT EXISTS dc_garrison_owner (account INT UNSIGNED NOT NULL, location INT UNSIGNED NOT NULL, since TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (account)) ENGINE=InnoDB")
        for _, t in ipairs({ "dc_garrison_object", "dc_garrison_decor" }) do   -- price columns (added after the first release)
            if not CharDBQuery("SHOW COLUMNS FROM " .. t .. " LIKE 'paid'") then
                CharDBQuery("ALTER TABLE " .. t .. " ADD COLUMN paid INT UNSIGNED NOT NULL DEFAULT 0, ADD COLUMN pcur VARCHAR(16) NOT NULL DEFAULT ''")
            end
        end
        -- one-time: a kind that became multi-instance decor may still have an old single-instance row, which would respawn unmanaged
        if not Meta("migrated_multi_kinds") then
            local ms = {}
            for _, c in ipairs(G.CATALOG) do if c.multi then ms[#ms + 1] = Q(c.kind) end end
            if #ms > 100 then   -- only with a sane catalog
                exec("DELETE FROM dc_garrison_object WHERE kind IN (" .. table.concat(ms, ",") .. ")")
                SetMeta("migrated_multi_kinds", "1")
            end
        end
        -- rows whose kind is not in the catalog are NOT deleted (SpawnOne ignores them); just say so
        local ks = {}
        for _, c in ipairs(G.CATALOG) do ks[#ks + 1] = Q(c.kind) end
        if #ks > 100 then
            for _, t in ipairs({ "dc_garrison_object", "dc_garrison_decor" }) do
                local q = CharDBQuery("SELECT COUNT(*) FROM " .. t .. " WHERE kind NOT IN (" .. table.concat(ks, ",") .. ")")
                if q and q:GetUInt32(0) > 0 then print("[garrison] " .. q:GetUInt32(0) .. " row(s) in " .. t .. " use a kind that is not in the catalog (kept, not spawned)") end
            end
        end
    end

    -- ---- ownership: one garrison location per account ----
    function S.LoadOwners()
        local out = {}
        local q = CharDBQuery("SELECT account, location FROM dc_garrison_owner")
        if q then repeat out[q:GetUInt32(0)] = q:GetUInt32(1) until not q:NextRow() end
        return out
    end
    function S.DeleteAccountData(acc)   -- everything an account placed (not the ownership row)
        acc = N(acc)
        exec("DELETE FROM dc_garrison_object WHERE account=" .. acc)
        exec("DELETE FROM dc_garrison_decor WHERE account=" .. acc)
        exec("DELETE FROM dc_garrison_setting WHERE account=" .. acc)
    end
    function S.Claim(acc, loc)   -- leftovers of an earlier garrison of this account are removed first, so a new claim always starts empty
        S.DeleteAccountData(acc)
        exec(string.format("REPLACE INTO dc_garrison_owner (account, location) VALUES (%d,%d)", N(acc), N(loc)))
    end
    function S.Abandon(acc)
        S.DeleteAccountData(acc)
        exec("DELETE FROM dc_garrison_owner WHERE account=" .. N(acc))   -- last
    end
    function S.PurgeGoneAccounts()   -- garrisons of deleted accounts. Skipped unless the auth database clearly works.
        local total = AuthDBQuery("SELECT COUNT(*) FROM account")
        if not total or total:GetUInt32(0) < 1 then return 0 end
        local gone = {}
        local q = CharDBQuery("SELECT account FROM dc_garrison_owner")
        if q then repeat
            local a = q:GetUInt32(0)
            if not AuthDBQuery("SELECT id FROM account WHERE id=" .. a) then gone[#gone + 1] = a end
        until not q:NextRow() end
        for _, a in ipairs(gone) do S.Abandon(a); print("[garrison] removed the garrison of deleted account " .. a) end
        return #gone
    end

    -- ---- layout (single-instance objects) and decor (many instances) ----
    function S.LoadLayout(acc, loc)
        local rows = {}
        local q = CharDBQuery(string.format("SELECT kind, x, y, z, o, paid, pcur FROM dc_garrison_object WHERE account=%d AND location=%d", N(acc), N(loc)))
        if q then repeat
            rows[#rows + 1] = { kind = q:GetString(0), x = q:GetFloat(1), y = q:GetFloat(2), z = q:GetFloat(3), o = q:GetFloat(4), paid = q:GetUInt32(5), pcur = q:GetString(6) }
        until not q:NextRow() end
        return rows
    end
    function S.LoadDecor(acc, loc)
        local rows = {}
        local q = CharDBQuery(string.format("SELECT id, kind, x, y, z, o, paid, pcur FROM dc_garrison_decor WHERE account=%d AND location=%d", N(acc), N(loc)))
        if q then repeat
            rows[#rows + 1] = { did = q:GetUInt32(0), kind = q:GetString(1), x = q:GetFloat(2), y = q:GetFloat(3), z = q:GetFloat(4), o = q:GetFloat(5), paid = q:GetUInt32(6), pcur = q:GetString(7) }
        until not q:NextRow() end
        return rows
    end
    function S.SaveObject(acc, loc, r)
        exec(string.format("REPLACE INTO dc_garrison_object (account, location, kind, x, y, z, o, paid, pcur) VALUES (%d,%d,%s,%f,%f,%f,%f,%d,%s)",
            N(acc), N(loc), Q(r.kind), r.x, r.y, r.z, r.o, N(r.paid), Q(r.pcur or "")))
    end
    function S.MoveObject(acc, loc, kind, r)
        exec(string.format("UPDATE dc_garrison_object SET x=%f, y=%f, z=%f, o=%f WHERE account=%d AND location=%d AND kind=%s", r.x, r.y, r.z, r.o, N(acc), N(loc), Q(kind)))
    end
    function S.DeleteObject(acc, loc, kind)
        exec(string.format("DELETE FROM dc_garrison_object WHERE account=%d AND location=%d AND kind=%s", N(acc), N(loc), Q(kind)))
    end
    local nextDid = 1
    function S.NextDecorId()
        if nextDid == 1 then   -- first call: continue after the highest id in the table
            local q = CharDBQuery("SELECT IFNULL(MAX(id),0) FROM dc_garrison_decor")
            nextDid = (q and q:GetUInt32(0) or 0) + 1
        end
        nextDid = nextDid + 1
        return nextDid - 1
    end
    function S.InsertDecor(acc, loc, r)
        exec(string.format("INSERT INTO dc_garrison_decor (id, account, location, kind, x, y, z, o, paid, pcur) VALUES (%d,%d,%d,%s,%f,%f,%f,%f,%d,%s)",
            N(r.did), N(acc), N(loc), Q(r.kind), r.x, r.y, r.z, r.o, N(r.paid), Q(r.pcur or "")))
    end
    function S.MoveDecor(acc, did, r)
        exec(string.format("UPDATE dc_garrison_decor SET x=%f, y=%f, z=%f, o=%f WHERE id=%d AND account=%d", r.x, r.y, r.z, r.o, N(did), N(acc)))
    end
    function S.DeleteDecor(acc, did) exec(string.format("DELETE FROM dc_garrison_decor WHERE id=%d AND account=%d", N(did), N(acc))) end
    function S.ClearDecor(acc, loc) exec(string.format("DELETE FROM dc_garrison_decor WHERE account=%d AND location=%d", N(acc), N(loc))) end

    -- ---- per garrison settings (pets roam or stay home) ----
    function S.GetRoam(acc, loc)
        local q = CharDBQuery(string.format("SELECT roam FROM dc_garrison_setting WHERE account=%d AND location=%d", N(acc), N(loc)))
        return not q or q:GetUInt32(0) ~= 0     -- default: pets explore
    end
    function S.SetRoam(acc, loc, on)
        exec(string.format("REPLACE INTO dc_garrison_setting (account, location, roam) VALUES (%d,%d,%d)", N(acc), N(loc), on and 1 or 0))
    end

    -- ---- "logged out inside a garrison" marker (character guid) ----
    function S.MarkLogout(guid) exec("REPLACE INTO dc_garrison_logout (guid) VALUES (" .. N(guid) .. ")") end
    function S.ConsumeLogout(guid)   -- true if the character logged out inside a garrison; the marker is removed
        local q = CharDBQuery("SELECT guid FROM dc_garrison_logout WHERE guid=" .. N(guid))
        if not q then return false end
        exec("DELETE FROM dc_garrison_logout WHERE guid=" .. N(guid))
        return true
    end

    -- ---- spawn registry: every temporary spawn is recorded so a reload / crash can never leave orphans ----
    function S.RegSpawn(low, t, entry, map)
        exec(string.format("REPLACE INTO dc_garrison_spawn (low, t, entry, map) VALUES (%d,%s,%d,%d)", N(low), Q(t), N(entry), N(map)))
    end
    function S.UnregSpawn(t, low) exec(string.format("DELETE FROM dc_garrison_spawn WHERE low=%d AND t=%s", N(low), Q(t))) end
    function S.ListSpawns()
        local out = {}
        local q = CharDBQuery("SELECT low, t, entry, map FROM dc_garrison_spawn")
        if q then repeat out[#out + 1] = { low = q:GetUInt32(0), t = q:GetString(1), entry = q:GetUInt32(2), map = q:GetUInt32(3) } until not q:NextRow() end
        return out
    end
    function S.ClearSpawns() exec("DELETE FROM dc_garrison_spawn") end
    function S.CountSpawns()
        local q = CharDBQuery("SELECT COUNT(*) FROM dc_garrison_spawn")
        return q and q:GetUInt32(0) or -1
    end

    -- ---- companions (pets): which spell gives which creature (world.dc_companion), which spells a character knows ----
    function S.CompanionMap()
        local out = {}
        local q = WorldDBQuery("SELECT spell, npc FROM dc_companion")
        if q then repeat out[q:GetUInt32(0)] = q:GetUInt32(1) until not q:NextRow() end
        return out
    end
    function S.KnownSpells(guid)
        local out = {}
        local q = CharDBQuery("SELECT spell FROM character_spell WHERE guid=" .. N(guid))
        if q then repeat out[#out + 1] = q:GetUInt32(0) until not q:NextRow() end
        return out
    end
    function S.InnTrigger(guid)   -- the tavern a character is resting in (0 = none)
        local q = CharDBQuery("SELECT innTriggerId FROM characters WHERE guid=" .. N(guid))
        return q and q:GetUInt32(0) or 0
    end

    S.Init()
    S.PurgeGoneAccounts()
end

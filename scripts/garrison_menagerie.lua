-- Garrison module 11/14: Menagerie (NPC 900003 "Breanni - Menagerie").
-- Needs the Menagerie placed. Up to maxPets of the OWNER-account character's learned companions are spawned (temporary, never saved)
-- and wander around the Menagerie; re-rolled every time the owner phases in. The owner can send them "home" (none spawned) via the NPC.
return function(G)
    local store, cfg, Say, Loc, active, inside = G.store, G.cfg, G.Say, G.locations.Get, G.active, G.inside
    local Reg, Unreg = G.Reg, G.Unreg
    local PET_SPREAD, PET_WANDER = 7, 8   -- spawn spread / how far (yd) from the Menagerie a pet strolls
    local REST_MIN, REST_MAX, STROLL_CHANCE, TICK_MS = 8, 30, 0.5, 2000   -- idle seconds between strolls; a pet may also just stay put
    local MEN_NPC = 900003
    math.randomseed(os.time())
    local StartStroll   -- defined below (RollPets calls it)

    -- Asks the live character (HasSpell), not the database: a pet learned a moment ago is only written to character_spell at the next save.
    local function KnownPets(player)
        local seen, list = {}, {}
        for spell, npc in pairs(G.COMPANIONS) do
            if not seen[npc] and player:HasSpell(spell) then seen[npc] = true; list[#list + 1] = npc end
        end
        table.sort(list)   -- stable before the shuffle
        return list
    end

    local function DespawnPets(h)   -- h.pets also holds the pick marker and the radius ring (garrison_props.lua): they go too
        for i = #h.pets, 1, -1 do
            local pet = h.pets[i]
            local map = GetMapById(pet.map, 0)
            local obj = map and map:GetWorldObject(pet.guid)
            if obj then obj:DespawnOrUnsummon(0) end
            Unreg("c", pet.low)
            h.pets[i] = nil
        end
    end

    local function RollPets(h, owner, player, forceOn)   -- player = the owner's online character
        DespawnPets(h)
        local row = h.rows and h.rows["menagerie"]
        if not row or not (forceOn or store.GetRoam(owner, h.loc)) then return end   -- forceOn: the setting write is still queued, so do not re-read it
        local pool = KnownPets(player)
        for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
        local loc = Loc(h.loc)
        for i = 1, math.min(cfg.maxPets, #pool) do
            local ang, dist = math.random() * 6.2832, 1.5 + math.random() * PET_SPREAD
            local obj = PerformIngameSpawn(1, pool[i], loc.map, 0, row.x + math.cos(ang) * dist, row.y + math.sin(ang) * dist, row.z + 0.3, math.random() * 6.2832, false, 0, h.bit)
            if obj then
                h.pets[#h.pets + 1] = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map, pet = true, nxt = os.time() + math.random(REST_MIN, REST_MAX) }   -- track first, configure after
                Reg(obj, "c", loc.map)
                obj:SetPhaseMask(h.bit, true)
                obj:SetReactState(0)             -- passive
                StartStroll()
                pcall(function() obj:SetWalk(true) end)   -- they amble, never run; they stand still until the stroll tick below sends them somewhere
            end
        end
    end
    -- Pets hang out: one global timer; every pet rests 8-30 s, then (50%) strolls to a spot near the Menagerie at walking pace, then rests again.
    local strollEv
    local function StrollTick()
        local now, any = os.time(), false
        for _, h in pairs(active) do
            local row = h.rows and h.rows["menagerie"]
            for _, pet in ipairs(h.pets) do
                if pet.pet then
                    any = true
                    if row and now >= pet.nxt then
                        pet.nxt = now + math.random(REST_MIN, REST_MAX)
                        if math.random() < STROLL_CHANCE then
                            local map = GetMapById(pet.map, 0)
                            local obj = map and map:GetWorldObject(pet.guid)
                            if obj then
                                local ang, dist = math.random() * 6.2832, 1.5 + math.random() * PET_WANDER   -- short, varied strolls
                                local tx, ty, tz = row.x + math.cos(ang) * dist, row.y + math.sin(ang) * dist, obj:GetZ()
                                pcall(function() obj:SetHomePosition(tx, ty, tz, obj:GetO()) end)   -- the new spot becomes "home": nothing pulls the pet back to where it spawned
                                pcall(function() obj:MoveTo(1, tx, ty, tz, false) end)
                            end
                        end
                    end
                end
            end
        end
        if not any and strollEv then RemoveEventById(strollEv); strollEv = nil end
    end
    function StartStroll() if not strollEv then strollEv = CreateLuaEvent(StrollTick, TICK_MS, 0) end end
    G.Menagerie.Roll, G.Menagerie.Clear = RollPets, DespawnPets

    G.OnEnter(function(player, h, owner) if player:GetAccountId() == owner then RollPets(h, owner, player) end end)   -- the owner phases in: fresh set of pets
    G.OnClose(function(h) DespawnPets(h) end)

    RegisterCreatureGossipEvent(MEN_NPC, 1, function(event, player, creature)
        local owner = inside[player:GetGUIDLow()]
        local h = owner and active[owner]
        if not h then Say(player, "The Menagerie only works inside a garrison."); return true end
        player:GossipClearMenu()
        if owner ~= player:GetAccountId() then
            player:GossipMenuAddItem(0, "Only the garrison owner can change this.", 0, 99, false)
        elseif store.GetRoam(owner, h.loc) then
            player:GossipMenuAddItem(0, "Have all pets stay home", 0, 2, false)
            player:GossipMenuAddItem(0, "Pick a new set of pets", 0, 3, false)
        else
            player:GossipMenuAddItem(0, "Allow pets to explore the garrison", 0, 1, false)
        end
        player:GossipSendMenu(1, creature)
        return true
    end)
    RegisterCreatureGossipEvent(MEN_NPC, 2, function(event, player, creature, sender, intid)
        player:GossipComplete()
        local owner = inside[player:GetGUIDLow()]
        local h = owner and active[owner]
        if not h or owner ~= player:GetAccountId() or intid == 99 then return true end
        if intid == 1 then store.SetRoam(owner, h.loc, true); RollPets(h, owner, player, true); Say(player, "Your pets are exploring the garrison.")
        elseif intid == 2 then store.SetRoam(owner, h.loc, false); DespawnPets(h); Say(player, "Your pets are staying home.")
        elseif intid == 3 then RollPets(h, owner, player); Say(player, "A new set of pets arrives.") end
        return true
    end)
end

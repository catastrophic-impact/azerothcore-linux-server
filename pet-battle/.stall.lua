package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local function mirror(b) return { E = b.P, P = b.E, active = { E = b.active.P, P = b.active.E }, rng = b.rng } end
local pairsList = { { 3103, 708, 20 }, { 17348, 2169, 25 }, { tonumber(arg[1]), tonumber(arg[2]), 1 } }
for _, pr in ipairs(pairsList) do
  if pr[1] and pr[2] and D.species[pr[1]] and D.species[pr[2]] then
    local stalls, n, shown = 0, 600, false
    for seed = 1, n do
        math.randomseed(seed)
        local pa, pb = C.NewPet(pr[1], pr[3], nil, nil, { quality = 2 }), C.NewPet(pr[2], pr[3], nil, nil, { quality = 2 })
        local b = C.NewBattle({ pa }, { pb }); local done = false
        local used = {}
        for r = 1, 300 do
            local ev, st = C.Round(b, C.AI(mirror(b)), C.AI(b))
            for _, x in ipairs(ev) do if x.k == "act" then used[x.side .. ":" .. x.name] = (used[x.side .. ":" .. x.name] or 0) + 1 end end
            if st == "win" or st == "loss" then done = true; break end
        end
        if not done then stalls = stalls + 1
            if not shown then shown = true
                local t = {}; for k, v in pairs(used) do t[#t + 1] = k .. "x" .. v end; table.sort(t)
                print(string.format("  first stall seed %d: A hp %d/%d B hp %d/%d; abilities used: %s", seed, pa.hp, pa.max, pb.hp, pb.max, table.concat(t, ", ")))
                local sa, sb = {}, {}
                for _, a in ipairs(pa.auras) do sa[#sa + 1] = a.id .. "(" .. a.left .. ")" end; for _, a in ipairs(pb.auras) do sb[#sb + 1] = a.id .. "(" .. a.left .. ")" end
                print("  auras A: " .. table.concat(sa, " ") .. " | B: " .. table.concat(sb, " "))
            end
        end
    end
    print(string.format("%s vs %s L%d: %d stalls in %d duels", D.species[pr[1]].name, D.species[pr[2]].name, pr[3], stalls, n))
  end
end

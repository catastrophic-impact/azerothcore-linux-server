-- readable 1v1 duel log: luajit pet-battle/trace_duel.lua <speciesA> <speciesB> [level] [seed]
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); require("pb_retail"); require("pb_rules"); local C = require("pb_core")
local a, b2, lv, seed = tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3]) or 3, tonumber(arg[4]) or 1
math.randomseed(seed)
local pa, pb = C.NewPet(a, lv, nil, nil, { quality = 2 }), C.NewPet(b2, lv, nil, nil, { quality = 2 })
local b = C.NewBattle({ pa }, { pb })
local function mirror(x) return { E = x.P, P = x.E, active = { E = x.active.P, P = x.active.E }, rng = x.rng } end
print(string.format("A %s (%s) hp %d pow %.0f spd %.0f | B %s (%s) hp %d pow %.0f spd %.0f", D.species[a].name, pa.family, pa.max, pa.power, pa.speed, D.species[b2].name, pb.family, pb.max, pb.power, pb.speed))
for r = 1, (tonumber(arg[5]) or 40) do
    local ev, st = C.Round(b, C.AI(mirror(b)), C.AI(b)); local line = {}
    for _, x in ipairs(ev) do
        if x.k == "act" then line[#line + 1] = x.side .. ":" .. x.name
        elseif x.k == "dmg" then line[#line + 1] = string.format("%s>%s -%d%s", x.side, x.tside, x.dmg, x.crit and "!" or "")
        elseif x.k == "dot" then line[#line + 1] = x.side .. " dot -" .. x.dmg
        elseif x.k == "heal" then line[#line + 1] = x.side .. " heal +" .. x.amt
        elseif x.k == "dodge" then line[#line + 1] = (x.text or "dodge") .. "@" .. x.side
        elseif x.k == "stunned" then line[#line + 1] = "stunned@" .. x.side
        elseif x.k == "buff" or x.k == "debuff" then line[#line + 1] = x.k .. ":" .. x.what .. "@" .. x.side end
    end
    print(string.format("R%02d  A %3d/%d  B %3d/%d  %s", r, pa.hp, pa.max, pb.hp, pb.max, table.concat(line, "  ")))
    if st == "win" or st == "loss" then print("RESULT", st == "win" and "A wins" or "B wins"); break end
end

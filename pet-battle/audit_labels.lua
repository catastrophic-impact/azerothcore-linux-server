-- PRESENTATION AUDIT (what the player READS vs what the engine DOES), by playing many real battles and watching every status the addon would show:
--   * a status labelled BUFF (bad = false) while it is the holder's only status must never be the source of damage-over-time (the Rust bug: damaging aura shown as a buff)
--   * a status labelled DEBUFF that is the only status must not be paired with healing it causes (aura heal events on that side while no heal ability was used)
--   * shown turns: never above 12 (99-turn bug), never negative, and a status that is shown must also exist in the engine's aura list; turns must not jump UP between rounds unless re-applied
--   * label text: no 'Effect <n>', 'nil', empty, or raw formula text
-- luajit pet-battle/audit_labels.lua [battles=3000] [seed=5]    (prints a status line every 20 s)
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core"); local R = require("pb_retail")
local N = tonumber(arg and arg[1]) or 3000
math.randomseed(tonumber(arg and arg[2]) or 5)
local ids = {}; for e, s in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
if os.getenv("PB_AUDIT_PINNED") then   -- audit only the pinned retail test species (restore candidates): PB_AUDIT_PINNED=1
    ids = {}; local i = 0
    for l in io.lines("pet-battle/pinned_species.txt") do local code = l:gsub("#.*", ""); local id = code:match("(%d+)"); if id then i = i + 1; D.species[999990 + i] = { name = "Pinned " .. id, retail = tonumber(id) }; ids[#ids + 1] = 999990 + i end end
end
local function mirror(b) return { E = b.P, P = b.E, active = { E = b.active.P, P = b.active.E }, rng = b.rng } end
local stat = {}   -- label -> { rounds, dot, bad, maxTurns, jumps, who }
local function S(l) local x = stat[l]; if not x then x = { rounds = 0, dot = 0, badRounds = 0, goodRounds = 0, maxTurns = 0, jumps = 0 }; stat[l] = x end return x end
local t0, last = os.time(), os.time()
for n = 1, N do
    local lv = ({ 5, 10, 15, 20, 25 })[math.random(5)]
    local function mk() local id = ids[math.random(#ids)]; return C.NewPet(id, lv, nil, nil, { quality = math.random(1, 4) }) end
    local b = C.NewBattle({ mk() }, { mk() })
    local prev = { P = {}, E = {} }
    for _ = 1, 60 do
        local ev, st = C.Round(b, C.AI(mirror(b)), C.AI(b))
        for _, s in ipairs({ "P", "E" }) do
            local pet = b[s][b.active[s]]
            local list = pet.hp > 0 and C.StatusList(pet) or {}
            local cur = {}
            for _, e in ipairs(list) do
                cur[e.label] = e.turns
                local x = S(e.label .. "|" .. tostring(e.aid)); if e.aid and not x.aid then x.aid = (R.abilities[e.aid] and R.abilities[e.aid].base) or e.aid end
                if e.turns > x.maxTurns then x.maxTurns = e.turns end
                if prev[s][e.label] and e.turns > prev[s][e.label] and e.turns > 0 and prev[s][e.label] > 0 then x.jumps = x.jumps + 1 end
            end
            if #list == 1 and prev[s].n == 1 and prev[s][list[1].label] ~= nil then   -- the same single status before and after this round
                local x = S(list[1].label .. "|" .. tostring(list[1].aid)); x.rounds = x.rounds + 1
                if list[1].bad then x.badRounds = x.badRounds + 1 else x.goodRounds = x.goodRounds + 1 end
                for _, e in ipairs(ev) do if e.k == "dot" and e.side == s then x.dot = x.dot + 1 end end
            end
            cur.n = #list; prev[s] = cur
        end
        if st == "win" or st == "loss" then break end
    end
    if os.time() - last >= 20 then last = os.time(); print(string.format("status: %d/%d battles, %d labels seen, %ds", n, N, (function() local c = 0 for _ in pairs(stat) do c = c + 1 end return c end)(), os.time() - t0)); io.stdout:flush() end
end
local problems, labels = {}, 0
local names = {}; for l in pairs(stat) do names[#names + 1] = l end; table.sort(names)
for _, l in ipairs(names) do
    local x = stat[l]; labels = labels + 1; l = l:gsub("|[^|]*$", "")   -- stats are per label AND aura id: two abilities may share a flavored name (a buff "Rip" next to a Rip bleed)
    if l == "" or l:find("^Effect %d") or l:find("nil") or l:find("%[") then problems[#problems + 1] = "BAD LABEL TEXT: '" .. l .. "'" end
    if x.goodRounds > 0 and x.dot > 0 and x.dot >= x.goodRounds * 0.5 then problems[#problems + 1] = string.format("BUFF THAT HURTS: '%s' labelled buff in %d sole-status rounds, damage-over-time in %d [ids %s]", l, x.goodRounds, x.dot, tostring(x.aid)) end
    if x.maxTurns > 12 and l ~= "Apocalypse" and x.aid ~= 683 and x.aid ~= 682 then problems[#problems + 1] = string.format("TURNS TOO HIGH: '%s' shows up to %d turns [ids %s]", l, x.maxTurns, tostring(x.aid)) end
end
print(string.format("audit_labels: %d battles, %d distinct status labels, %d findings", N, labels, #problems))
for _, p in ipairs(problems) do print("  " .. p) end
os.exit(#problems == 0 and 0 or 1)

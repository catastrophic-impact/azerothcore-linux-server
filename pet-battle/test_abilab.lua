-- Ability lab (.pblab): the y / n handling, with a fake server and a fake clock. The user types answers in chat, one per ability, possibly several in a row ("y y n n y"):
-- every answer must be counted for the ability it was meant for, never skip ahead, and ordinary chat must never be swallowed.
package.path = "pet-battle/lab/?.lua;scripts/?.lua;" .. package.path
local timers, now = {}, 0
function CreateLuaEvent(f, ms) timers[#timers + 1] = { f = f, t = now + ms } end
local said, appended = {}, {}
local player = { GetGUIDLow = function() return 7 end, GetGUID = function() return 700 end, GetGMRank = function() return 3 end, GetMap = function() return { GetWorldObject = function() return nil end } end }
function GetPlayerByGUID() return player end
package.preload["pb_data"] = function() return { StandIn = function() return nil end } end
package.preload["pb_store"] = function() return { Scale = function() return 1 end } end
local hooks = {}
function RegisterPlayerEvent(ev, f) hooks[ev] = f end
package.preload["pb_abilab_data"] = function() return {
  { id = 1, name = "Alpha", text = "a", species = 299, mode = "melee", hits = 1, cands = { { kind = "spell", spell = 11, label = "A1", mode = "melee" } } },
  { id = 2, name = "Beta", text = "b", species = 299, mode = "ranged", hits = 1, cands = { { kind = "spell", spell = 21, label = "B1", mode = "ranged" }, { kind = "spell", spell = 22, label = "B2", mode = "ranged" } } },
  { id = 3, name = "Gamma", text = "c", species = 299, mode = "self", hits = 1, cands = { { kind = "spell", spell = 31, label = "G1", mode = "self" } } },
  { id = 4, name = "Delta", text = "d", species = 299, mode = "self", hits = 1, cands = { { kind = "spell", spell = 41, label = "D1", mode = "self" } } },
  { id = 5, name = "Defer", text = "e", species = 299, mode = "defer", hits = 1, cands = {} },
} end
package.preload["pb_review_data"] = function() return {
  { id = 11, name = "R1", text = "r1", species = 299, mode = "melee", hits = 1, cands = { { kind = "spell", spell = 111, label = "S1", mode = "melee" } } },
  { id = 12, name = "R2", text = "r2", species = 299, mode = "ranged", hits = 1, cands = { { kind = "spell", spell = 112, label = "S2", mode = "ranged" } } },
  { id = 13, name = "R3", text = "r3", species = 299, mode = "self", hits = 1, cands = { { kind = "spell", spell = 113, label = "S3", mode = "self" } } },
  { id = 14, name = "R4", text = "r4", species = 299, mode = "self", hits = 1, cands = { { kind = "spell", spell = 114, label = "S4", mode = "self" } } },
} end
dofile("pet-battle/lab/pb_abilab.lua")
local L = PB_ABILAB
local played = {}
L.Say = function(_, t) said[#said + 1] = t end
L.Big = function() end
L.Append = function(line) appended[#appended + 1] = line end
L.Now = function() return "T" end
L.SpawnPair = function() return true end
L.Play = function(S, item, cand) played[#played + 1] = item.name .. "/" .. cand.label; return 2000 end
local function run(ms) local stop = now + ms; while true do table.sort(timers, function(a, b) return a.t < b.t end); local nx = timers[1]; if not nx or nx.t > stop then break end; table.remove(timers, 1); now = nx.t; nx.f() end; now = stop end
local function chat(text) local r = hooks[18](18, player, text); return r == false end   -- true = the message was swallowed
local function lastSaid(pat) for i = #said, 1, -1 do if said[i]:find(pat, 1, true) then return said[i] end end end
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL: " .. m) end end

-- parser
local P = L.Parse
check(P("y") == "y" and P("N") == "n" and P(" r ") == "r", "plain answers")
local a, n = P("n: too slow"); check(a == "n" and n == "too slow", "n with comment")
a, n = P("Y;great one"); check(a == "y" and n == "great one", "y with comment")
check(P("yes") == nil and P("no") == nil and P("nope") == nil and P("hello") == nil and P("") == nil and P("yy") == nil and P("n u") == nil, "normal chat is not an answer")

-- no session: chat is never touched
check(chat("y") == false, "without a session nothing is swallowed")
hooks[42](42, player, "pblab 1")
check(#L.Items() == 4, "deferred abilities are not in the lab (" .. #L.Items() .. ")")
-- while the first effect is still playing: an early 'y' is swallowed but NOT counted
run(100); check(chat("y") == true, "an early answer is swallowed"); check(lastSaid("ignored"), "and the lab says it was ignored")
check(#appended == 0, "an early answer is not counted")
run(5000); check(lastSaid("Answer now"), "the lab asks for the answer when the effect is over")
-- the user types 'y y n n y' in one go: only the FIRST counts, for Alpha
check(chat("y") and chat("y") and chat("n") and chat("n") and chat("y"), "all five are swallowed")
check(#appended == 1 and appended[1]:find("Alpha") and appended[1]:find("\ty"), "exactly one answer counted, for Alpha: " .. tostring(appended[1]))
run(2000); check(played[#played] == "Beta/B1", "next is Beta, candidate 1: " .. tostring(played[#played]))
-- ordinary chat during the wait is not swallowed
run(2100); check(chat("hello everyone") == false, "ordinary chat passes")
check(chat("n: looks like a bolt, not a wave") == true, "n with comment is swallowed")
check(appended[2]:find("Beta") and appended[2]:find("B1") and appended[2]:find("looks like a bolt"), "Beta/B1 counted as n with the comment: " .. tostring(appended[2]))
run(2000); check(played[#played] == "Beta/B2", "after n the SAME ability's second candidate is next: " .. tostring(played[#played]))
run(2100); chat("r"); run(600); check(#appended == 2, "r is not counted"); run(1300); check(played[#played] == "Beta/B2", "r replays"); run(2100); chat("y"); check(appended[3]:find("Beta") and appended[3]:find("B2") and appended[3]:find("\ty"), "Beta/B2 counted y")
run(2000); check(played[#played] == "Gamma/G1", "Gamma next")
run(2100); chat("n"); run(2000); check(played[#played] == "Delta/D1", "n on the LAST candidate moves on to the next ability")
run(2100); chat("y: fine"); check(appended[5]:find("Delta") and appended[5]:find("fine"), "y with comment saved")
run(1300); check(lastSaid("Batch finished: 3 y, 2 n"), "summary: " .. tostring(lastSaid("Batch finished")))
check(chat("y") == false, "after the batch nothing is swallowed any more")
-- .pblab with no number: the next unsettled abilities (no y yet; answered candidates never come back; flagged retests come back with their NEW candidates)
do
  local rows = {   -- time, id, name, label=spell, answer
    { "T", "1", "Alpha", "A1=11", "y" }, { "T", "2", "Beta", "B1=21", "n" }, { "T", "4", "Delta", "D1=41", "y" } }
  L.ReadResults = function() return rows end
  local pend = L.Pending(); local names = {}
  for _, e in ipairs(pend) do names[#names + 1] = e.name .. "(" .. #e.cands .. ")" end
  check(table.concat(names, ",") == "Beta(1),Gamma(1)", "pending: Alpha and Delta have a y, Beta lost B1 and keeps B2, Gamma is unseen: " .. table.concat(names, ","))
  rows[2][5] = "y"   -- Beta's first candidate is good: its untried second candidate must NOT come back
  pend = L.Pending(); check(#pend == 1 and pend[1].name == "Gamma", "an ability with a y is settled even when it has untried candidates")
  rows[2][5] = "n"
  rows[#rows + 1] = { "T", "2", "Beta", "B2=22", "n" }
  pend = L.Pending(); check(#pend == 1 and pend[1].name == "Gamma", "an ability whose candidates were all answered n is not shown again")
  check(pend[1].cands[1].label == "G1", "its candidate is intact")
  L.Start(player, pend); run(100); hooks[42](42, player, "pblab stop")
  hooks[42](42, player, "pblab"); run(5000); check(lastSaid("1 abilities left in total") or lastSaid("abilities left in total"), "plain .pblab plays the pending list: " .. tostring(lastSaid("left in total")))
  chat("y"); run(2000); hooks[42](42, player, "pblab stop")
end
-- REVIEW (.pbreview): every ability once, y / n: reason, position kept, stop at any time, b = back
do
  local rows, files = {}, {}
  L.ReadResults = function() return rows end
  L.Append = function(line, file) files[#files + 1] = file; local c = {}; for x in (line .. "\t"):gmatch("([^\t]*)\t") do c[#c + 1] = x end; rows[#rows + 1] = c end
  played = {}
  hooks[42](42, player, "pbreview"); run(5000)
  check(played[#played] == "R1/S1", "review starts at the first ability: " .. tostring(played[#played]))
  check(chat("y") == true, "review answer swallowed"); check(files[1] == "logs/pb_review.tsv", "review results go to their own file: " .. tostring(files[1]))
  run(2000); check(played[#played] == "R2/S2", "next ability"); run(2100)
  chat("n: the bolt looks like a wave"); check(rows[2][5] == "n" and rows[2][6]:find("wave"), "n with the reason saved")
  run(2000); check(played[#played] == "R3/S3", "R3 next"); run(2100)
  chat("stop"); check(chat("y") == false, "after stop nothing is swallowed"); check(lastSaid("Your place is saved"), "stop says the place is kept")
  hooks[42](42, player, "pbreview"); run(5000)
  check(played[#played] == "R3/S3", "resume continues at the first ability without a verdict: " .. tostring(played[#played]))
  run(2100); chat("b"); run(900); run(5000); check(played[#played] == "R2/S2", "b goes back one: " .. tostring(played[#played]))
  run(100); chat("y"); check(rows[#rows][2] == "12" and rows[#rows][5] == "y", "the new answer for R2 is appended")
  run(2000); check(played[#played] == "R3/S3", "after re-answering, continue with the next ability WITHOUT a verdict (R3), not R2/R1 again: " .. tostring(played[#played]))
  run(2100); chat("y"); run(2000); run(2100); chat("y"); run(1300); check(lastSaid("REVIEW COMPLETE"), "completion message: " .. tostring(lastSaid("REVIEW")))
  hooks[42](42, player, "pbreview"); check(lastSaid("Review complete"), "a finished review says so")
end
-- stop
hooks[42](42, player, "pblab 1"); run(5000); hooks[42](42, player, "pblab stop"); check(chat("y") == false, "after .pblab stop nothing is swallowed")
if fails > 0 then print(fails .. " FAILURES"); os.exit(1) end
print("ability lab: answer handling OK (" .. #appended .. " answers counted)")

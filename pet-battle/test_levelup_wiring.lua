-- LEVEL-UP GRAPHIC wiring (the battle sim plays test teams, which earn no XP, so the real XP branch is not run there): every link must exist
local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local srv, add, fails = read("scripts/pb_battle.lua"), read("addons/wotlk_petbattle/Battle.lua"), 0
local function ok(c, m) if not c then fails = fails + 1; print("FAIL " .. m) end end
ok(srv:find("FX_LEVELUP = 47292", 1, true), "server: FX_LEVELUP must be the instant Level Up spell 47292 (24312 is a 7-day aura)")
ok(srv:find("if ups and ups > 0 then leveled = true end", 1, true), "server: level-up is detected from GrantXP's levels gained")
ok(srv:find("if leveled then Fx(GetObj(b, \"P\"), FX_LEVELUP", 1, true), "server: the burst is cast on the player's pet when it leveled")
ok(srv:find("leveled and 2600", 1, true), "server: the pet stays long enough to show the burst")
ok(add:find("LevelUpFx(name, lv)", 1, true) and add:find("if Num(ups) > 0 then", 1, true), "addon: banner shown when ups > 0")
ok(add:find('PlaySound, "LEVELUPSOUND"', 1, true), "addon: level-up sound")
ok(add:find('"Level Up!"', 1, true), "addon: banner text")
print(string.format("levelup wiring: %d problems", fails)); os.exit(fails == 0 and 0 or 1)

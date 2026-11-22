-- Test for scripts/bot_manager.lua WITHOUT a server (ALE faked): companions must be dismissed when the last real player leaves the group
-- or the group is disbanded, and must stay when another real player is still there.   usage: lua5.1 tools/test_botmanager.lua [-v]
local VERBOSE = arg and arg[1] == "-v"
local here = (arg[0]:match("^(.*)/tools/") or ".")
package.path = here .. "/scripts/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(cond, what) checks = checks + 1; if not cond then fails = fails + 1; print("FAIL: " .. what) elseif VERBOSE then print("ok:   " .. what) end end

package.preload["acore_msg"] = function() return { On = function() end, Send = function() end, Has = function() return true end } end
local timers, groupEv, online = {}, {}, {}
CreateLuaEvent = function(fn, delay, reps) timers[#timers + 1] = { fn = fn }; return #timers end
local function runTimers() local t = timers; timers = {}; for _, x in ipairs(t) do x.fn() end end
RegisterGroupEvent = function(ev, fn) groupEv[ev] = fn end
GetPlayerByGUID = function(g) return online[g] end
GetPlayersInWorld = function() return {} end

local cmds = {}
local function mk(low, name, bot)
    local p = { low = low, name = name, bot = bot }
    function p:IsBot() return self.bot end
    function p:GetGUIDLow() return self.low end
    function p:GetGUID() return self.low end
    function p:GetName() return self.name end
    function p:GetGroup() return nil end
    function p:GetClass() return 1 end
    function p:GetLevel() return 80 end
    function p:RunCommand(c) cmds[#cmds + 1] = name .. ": " .. c end
    online[low] = p
    return p
end
local function group(...) local m = { ... }; return { GetMembers = function() return m end, GetMembersCount = function() return #m end } end

local ok, err = pcall(dofile, here .. "/scripts/bot_manager.lua")
check(ok, "bot_manager.lua loads" .. (ok and "" or (": " .. tostring(err))))
check(groupEv[3] and groupEv[5], "member-remove and disband group events are registered")

local H, H2, B1, B2 = mk(1, "Human", false), mk(2, "Friend", false), mk(11, "Botone", true), mk(12, "Bottwo", true)

cmds = {}; groupEv[3](3, group(H, B1, B2), 1); runTimers()   -- the last real player leaves: the group still lists everybody at the hook
check(#cmds == 2 and cmds[1] == "Human: .playerbots bot remove Botone" and cmds[2] == "Human: .playerbots bot remove Bottwo", "last real player leaves: each companion is dismissed by name (" .. table.concat(cmds, " | ") .. ")")

cmds = {}; groupEv[3](3, group(H, H2, B1, B2), 1); runTimers()
check(#cmds == 0, "another real player is still in the group: the bots stay")

cmds = {}; groupEv[3](3, group(H, B1), 11); runTimers()
check(#cmds == 0, "a bot leaving does nothing")

cmds = {}; online[1] = nil; groupEv[3](3, group(H, B1), 1); runTimers(); online[1] = H
check(#cmds == 0, "leaver already offline: nothing (playerbots logs its bots out itself)")

cmds = {}; groupEv[3](3, group(B1, B2), 1); runTimers()
check(#cmds == 2, "leaver already removed from the member list: still dismisses")

cmds = {}; groupEv[5](5, group(H, B1, B2)); runTimers()
check(#cmds == 2, "disband with one real player: the bots are dismissed")

cmds = {}; groupEv[5](5, group(H, H2, B1)); runTimers()
check(#cmds == 0, "disband with two real players: nothing is dismissed")

cmds = {}; groupEv[3](3, group(H), 1); runTimers()
check(#cmds == 0, "no bots in the group: nothing to do")

print(checks .. " checks, " .. fails .. " failed"); os.exit(fails == 0 and 0 or 1)

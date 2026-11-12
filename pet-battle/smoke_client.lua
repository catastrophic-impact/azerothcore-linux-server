-- Headless client smoke test: luajit pet-battle/smoke_client.lua <addon.lua> <slash> ; stubs the WoW widget API generically
local file, msgs = arg[1], arg[2]
local Stub; Stub = setmetatable({}, { __index = function(t, k)
  if k == "GetText" then return function() return "" end end
  if k == "IsShown" then return function() return true end end
  if k == "GetWidth" or k == "GetHeight" or k == "GetTime" or k == "GetFrameLevel" then return function() return 100 end end
  return function(self, ...) return Stub end end, __call = function() return Stub end })
local sent, handlers = {}, {}
AcoreLib = { On = function(m, a, f) handlers[m .. "|" .. a] = f end, Send = function(m, a, p) sent[#sent + 1] = m .. "|" .. a .. "|" .. tostring(p) end, Solid = function() return Stub end, handlers = handlers }
function CreateFrame() return setmetatable({}, getmetatable(Stub)) end   -- a fresh table per frame (real frames keep their own fields)
UIParent, GameTooltip, DEFAULT_CHAT_FRAME = Stub, Stub, { AddMessage = function(_, t) print("CHAT:", t) end }
UISpecialFrames, SlashCmdList = {}, {}
function tinsert(t, v) t[#t + 1] = v end
function GetTime() return 0 end
function UnitName() return "x" end
local ok, err = pcall(dofile, file); if not ok then print("LOAD ERROR", err) os.exit(1) end
local slash = os.getenv("SLASH")
-- handlers must exist right after load (battles can start from a gossip menu without any slash command)
for _, need in ipairs(file:find("Pets") and { "pbj|pet", "pbj|team", "pbj|active", "pbj|done" } or { "pbt|begin", "pbt|st", "pbt|turn", "pbt|hp", "pbt|end", "pbt|done" }) do
  if not handlers[need] then print("ERROR handler not registered at load: " .. need) end
end
if os.getenv("SLASH") == "1" then for k, f in pairs(SlashCmdList) do local ok2, e2 = pcall(f, ""); print("slash", k, ok2 and "ok" or ("ERROR " .. tostring(e2))) end end
local n = 0
for line in (os.getenv("MSGS") or ""):gmatch("[^\n]+") do
  local m, a, p = line:match("^([%w_]+)|([%w_]+)|?(.*)$")
  local h = handlers[m .. "|" .. a]
  if not h then print("NO HANDLER", m, a) else local ok3, e3 = pcall(h, p); n = n + 1; if not ok3 then print("HANDLER ERROR", m .. "|" .. a, e3) end end
end
print("sent:", table.concat(sent, " ; "), " handled:", n)

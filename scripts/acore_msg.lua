-- ============================================================
-- ACORE messaging layer (server side, ALE)
-- Addon <-> server protocol over hidden addon messages.
--   wire format:  "<module>|<action>|<payload>"   (max ~240 chars)
--   client -> server: SendAddonMessage("ACORE", msg, "WHISPER", UnitName("player"))
--   server -> client: ACORE.Msg.Send(player, module, action, payload)
-- Other scripts: local Msg = require("acore_msg"); Msg.On("shop", "buy", function(player, payload) ... end)
-- ============================================================

ACORE = ACORE or {}
if ACORE.Msg then return ACORE.Msg end   -- already loaded (safe against double load)

local Msg = { PREFIX = "ACORE", handlers = {}, WHISPER = 7 }
ACORE.Msg = Msg

local MAX_LEN = 240

function Msg.On(module, action, fn)
    Msg.handlers[module .. "|" .. action] = fn
end

function Msg.Send(player, module, action, payload)
    if not player then return false end
    local text = module .. "|" .. action .. "|" .. tostring(payload or "")
    if #text > MAX_LEN then
        print("[ACORE.Msg] payload too long for " .. module .. "|" .. action .. " (" .. #text .. ")")
        return false
    end
    player:SendAddonMessage(Msg.PREFIX, text, Msg.WHISPER, player)
    return true
end

-- Long lists: sends several "<action>" messages, payload prefixed with "<i>/<n>;"
function Msg.SendChunks(player, module, action, parts)
    local n = #parts
    for i, part in ipairs(parts) do
        Msg.Send(player, module, action, i .. "/" .. n .. ";" .. part)
    end
end

local function OnAddonMessage(event, sender, msgType, prefix, msg, target)
    if prefix ~= Msg.PREFIX then return end
    if not sender or type(msg) ~= "string" or #msg > 255 then return false end
    local module, action, payload = msg:match("^([%w_]+)|([%w_]+)|?(.*)$")
    if not module then return false end
    local fn = Msg.handlers[module .. "|" .. action]
    if fn then
        local ok, err = pcall(fn, sender, payload)
        if not ok then print("[ACORE.Msg] handler error " .. module .. "|" .. action .. ": " .. tostring(err)) end
    end
    return false   -- swallow our own traffic so it never reaches chat/whisper targets
end

RegisterServerEvent(30, OnAddonMessage)   -- ADDON_EVENT_ON_MESSAGE

Msg.On("core", "ping", function(player, payload) Msg.Send(player, "core", "pong", payload) end)
print("[ACORE.Msg] messaging layer loaded")
return Msg

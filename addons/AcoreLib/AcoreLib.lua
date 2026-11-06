-- AcoreLib: tiny messaging layer shared by our addons. Wire format matches scripts/acore_msg.lua
-- usage:  AcoreLib.On("shop", "bal", function(payload) ... end);  AcoreLib.Send("shop", "buy", "1001")
AcoreLib = AcoreLib or {}
local L = AcoreLib
L.PREFIX = "ACORE"
L.handlers = L.handlers or {}

-- opaque panel behind a window's contents (the stock dialog backgrounds are see-through). inset = how far inside the border to start
function L.Solid(frame, inset, r, g, b)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetPoint("TOPLEFT", inset, -inset); t:SetPoint("BOTTOMRIGHT", -inset, inset); t:SetTexture(r or 0.07, g or 0.07, b or 0.09, 1)
    return t
end

function L.On(module, action, fn)
    L.handlers[module .. "|" .. action] = fn
end

function L.Send(module, action, payload)
    local text = module .. "|" .. action .. "|" .. tostring(payload or "")
    if #text > 240 then return false end
    SendAddonMessage(L.PREFIX, text, "WHISPER", UnitName("player"))   -- server hook swallows it
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    if prefix ~= L.PREFIX then return end
    local module, action, payload = msg:match("^([%w_]+)|([%w_]+)|?(.*)$")
    local fn = module and L.handlers[module .. "|" .. action]
    if fn then fn(payload, sender) end
end)

-- /acorelib ping : round-trip test against the server
SLASH_ACORELIB1 = "/acorelib"
SlashCmdList["ACORELIB"] = function(arg)
    L.On("core", "pong", function(p) print("|cff00ff00AcoreLib:|r server replied: " .. tostring(p)) end)
    L.Send("core", "ping", arg ~= "" and arg or "hello")
end

-- ============================================================
-- ACORE event bus (CORE): lets one addon announce something without knowing who (if anyone) listens.
--   local Bus = require("acore_bus")
--   Bus.On("companion_learned", function(player) ... end)    -- any addon may listen; nothing happens if nobody emits
--   Bus.Emit("companion_learned", player)                    -- any addon may emit; nothing happens if nobody listens
-- A failing listener is logged and never breaks the emitter or the other listeners.
-- Known events (keep this list current):
--   companion_learned(player)   the Shop taught a player a companion pet spell
-- ============================================================
ACORE = ACORE or {}
if ACORE.Bus then return ACORE.Bus end   -- already loaded (safe against double load)

local Bus = { listeners = {} }
ACORE.Bus = Bus

-- key (optional, e.g. the addon's name): registering the same key again REPLACES the earlier listener, so a script reload never doubles it
function Bus.On(event, fn, key)
    local l = Bus.listeners[event]; if not l then l = {}; Bus.listeners[event] = l end
    for i, e in ipairs(l) do if key and e.key == key then l[i] = { fn = fn, key = key }; return end end
    l[#l + 1] = { fn = fn, key = key }
end

function Bus.Emit(event, ...)
    for _, e in ipairs(Bus.listeners[event] or {}) do
        local ok, err = pcall(e.fn, ...)
        if not ok then print("[acore_bus] listener for '" .. event .. "' failed: " .. tostring(err)) end
    end
end

return Bus

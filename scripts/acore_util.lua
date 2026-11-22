-- ============================================================
-- ACORE small shared helpers (CORE). Everything here must work on a plain AzerothCore + mod-ale server.
--   local U = require("acore_util")
--   U.IsBot(player)   true only for a playerbot. False for a real player, nil, or on a server WITHOUT mod-playerbots (no IsBot in the API).
-- ============================================================
ACORE = ACORE or {}
if ACORE.Util then return ACORE.Util end   -- already loaded (safe against double load)

local U = {}
ACORE.Util = U

function U.IsBot(player)
    if not player then return false end
    local ok, v = pcall(function() return player:IsBot() end)
    return ok and v == true
end

return U

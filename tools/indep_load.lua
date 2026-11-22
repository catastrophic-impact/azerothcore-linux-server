-- usage: luajit indep_load.lua <dir with ONLY the component's lua_scripts> ; loads every script with a permissive game-API stub
local dir = arg[1]
package.path = dir .. "/?.lua"            -- ONLY this folder: anything not shipped with the component cannot be found
local noop = function() return nil end
setmetatable(_G, { __index = function(_, k) if type(k)=="string" and k:match("^[A-Z][a-z]") then return noop end end })
GARRISON_TEST = nil
local fails = 0
local p = io.popen("ls " .. dir .. "/*.lua"); local files = {}
for f in p:lines() do files[#files+1] = f end; p:close()
table.sort(files)
for _, f in ipairs(files) do
  local ok, err = pcall(dofile, f)
  if not ok then fails = fails + 1; print("LOAD FAIL " .. f:match("[^/]+$") .. ": " .. tostring(err):sub(1,200)) end
end
print(string.format("%s: %d scripts, %d failed to load", dir:match("[^/]+/lua_scripts$") or dir, #files, fails))
os.exit(fails == 0 and 0 or 1)

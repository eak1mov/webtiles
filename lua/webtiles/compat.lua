local compats = {
    ["Lua 5.1"] = function()
        local ok = pcall(require, "jit")
        if not ok then
            return require("webtiles.compat_5_1")
        else
            return require("webtiles.compat_luajit")
        end
    end,
    ["Lua 5.3"] = function() return require("webtiles.compat_5_3") end,
    ["Lua 5.4"] = function() return require("webtiles.compat_5_3") end,
}
return assert(compats[_VERSION], "Unsupported Lua Version: " .. _VERSION)()

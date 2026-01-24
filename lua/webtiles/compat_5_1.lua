local bit = require("bit") -- https://github.com/LuaDist/bitlib

local function unpack_I8(buf)
    local n = string.unpack("<I8", buf)
    assert(n <= math.maxinteger, "failed to unpack 64bit integer: " .. tostring(n))
    return n
end

local m = {}
m.bit = bit
m.cast = function(n) return n end
m.unpack_I4 = function(buf) return string.unpack("<I4", buf) end
m.unpack_I8 = unpack_I8
return m

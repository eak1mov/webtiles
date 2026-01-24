local bit = require("bit")
local ffi = require("ffi")

local function cast(n)
    return ffi.cast("uint64_t", n)
end

local m = {}
m.bit = bit
m.cast = cast
m.unpack_I4 = function(buf) return ffi.cast("uint32_t*", buf)[0] end
m.unpack_I8 = function(buf) return ffi.cast("uint64_t*", buf)[0] end
return m

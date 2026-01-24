local m = {}
m.bit = {
    band = function(a, b) return a & b end,
    bor = function(a, b) return a | b end,
    lshift = function(a, b) return a << b end,
    rshift = function(a, b) return a >> b end,
}
m.cast = function(n) return n end
m.unpack_I4 = function(buf) return string.unpack("<I4", buf) end
m.unpack_I8 = function(buf) return string.unpack("<I8", buf) end
return m

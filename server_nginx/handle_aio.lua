local function read_at(filePath, offset, size)
    local f = assert(io.open(filePath, "rb"))
    assert(f:seek("set", offset))
    local buf = assert(f:read(size))
    f:close()
    return buf
end

local m = {}
m.read_at = read_at
return m

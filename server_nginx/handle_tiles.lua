local wt = require("webtiles")
--local wt = require("webtiles_basic")

local filePath = "/tilesets/example.wtiles";
local match, _, z, x, y = string.find(ngx.var.uri, "^/tiles/(%d+)/(%d+)/(%d+)$")

if not match then
    ngx.exit(404)
end

x = tonumber(x)
y = tonumber(y)
z = tonumber(z)

-- TODO: add range checks
if x == nil or y == nil or z == nil then
    ngx.exit(400)
end

local f = io.open(filePath, "rb")
if f == nil then
    ngx.exit(404)
end

local fileAccess = function (offset, size)
    assert(f:seek("set", offset))
    return assert(f:read(size))
end

-- TODO: handle errors with pcall
local location = wt.readTileLocation(x, y, z, fileAccess)

-- TODO: use direct fileAccess instead of run_worker_thread when filePath is in tmpfs:
-- local tileData = wt.readTileData(x, y, z, fileAccess)
-- ngx.print(tileData)

f:close()

if location.size == 0 then
    ngx.exit(204) -- HTTP_NO_CONTENT
end

local ok, buf = ngx.run_worker_thread(
    "tiles_aio_threadpool", "handle_aio", "read_at", filePath, location.offset, location.size
)
if not ok then
    ngx.log(ngx.ERR, "read_at failed: " .. (buf or "???"))
    ngx.exit(500)
end

--ngx.header["Content-Encoding"] = contentEncoding
--ngx.header["Content-Type"] = contentType
ngx.print(buf)

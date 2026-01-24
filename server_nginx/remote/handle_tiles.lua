local wt = require("webtiles")
-- local ResponseParams = require("webtiles.fbs.ResponseParams")

local s3Location = "/s3_proxy/"
local fileName = "example.wtiles"
local match, _, z, x, y = string.find(ngx.var.uri, '^/tiles/(%d+)/(%d+)/(%d+)$')

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

local fileAccess = function (offset, size)
    local res = ngx.location.capture(s3Location .. fileName, {
        headers = {["Range"] = "bytes=" .. offset .. "-" .. offset + size - 1}
    })
    if res.status == 404 then
        ngx.exit(404)
    end
    if res.status == 200 then
        ngx.log(ngx.ERR, "HTTP Range headers are not supported?"
            .. " (expected size " .. size .. ", got " .. #res.body .. ")")
        ngx.exit(500)
    end
    if res.status ~= 206 then
        ngx.log(ngx.ERR, "Request to S3 failed: " .. res.status)
        ngx.exit(500)
    end
    if res.truncated then
        ngx.log(ngx.ERR, "Truncated response from S3")
        ngx.exit(500)
    end
    return res.body
end

local tileData, paramsData = wt.readTileData(x, y, z, fileAccess)

-- local params = ResponseParams.GetRootAsResponseParams(paramsData, 0)
-- ngx.header["Content-Encoding"] = params:ContentEncoding()
-- ngx.header["Content-Type"] = params:ContentType()

ngx.print(tileData)

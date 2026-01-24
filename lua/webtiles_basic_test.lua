local webtiles = require("webtiles_basic")
local compat = require("webtiles.compat")

local BAZEL_TEST = os.getenv("BAZEL_TEST")
local TESTDATA_PATH = BAZEL_TEST and "testdata/" or "../bazel-bin/testdata/"

local function getData(filepath, offset, size)
    local f = assert(io.open(filepath, "rb"))
    f:seek("set", offset)
    local buf = f:read(size)
    f:close()
    return buf
end

local function runTest(indexFileName, wtFileName)
    print("running", indexFileName, wtFileName)

    local fileAccess = function (offset, size)
        return getData(TESTDATA_PATH .. wtFileName, offset, size)
    end

    local f = assert(io.open(TESTDATA_PATH .. indexFileName, "rb"))
    while true do
        local block = f:read(24)
        if not block then break end

        local x = compat.unpack_I4(string.sub(block, 1))
        local y = compat.unpack_I4(string.sub(block, 5))
        local z = compat.unpack_I4(string.sub(block, 9))
        --local size = compat.unpack_I4(string.sub(block, 13))
        local offset = compat.unpack_I8(string.sub(block, 17))

        local tileData = webtiles.readTileData(x, y, z, fileAccess)

        assert(tileData == tostring(tonumber(offset)),
            "expected: " .. tostring(tonumber(offset)) .. ", actual: " .. tileData)
    end
    f:close()
end

runTest("small.index", "small_basic.wtiles")
runTest("medium.index", "medium_basic.wtiles")
--runTest("large.index", "large_basic.wtiles")
print("done!")

local webtiles = require("webtiles")
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

    local actualData, extendedHeader = webtiles.readTileData(0, 0, 0, fileAccess)
    assert(indexFileName ~= "empty.index" or actualData == "", "actual: " .. actualData)
    assert(indexFileName ~= "data42.index" or actualData == "42", "actual: " .. actualData)
    assert(extendedHeader == "extended_header", "actual: " .. extendedHeader)

    local f = io.open(TESTDATA_PATH .. indexFileName, "rb")
    while true do
        local block = f:read(24)
        if not block then break end

        local x = compat.unpack_I4(string.sub(block, 1))
        local y = compat.unpack_I4(string.sub(block, 5))
        local z = compat.unpack_I4(string.sub(block, 9))
        --local size = compat.unpack_I4(string.sub(block, 13))
        local offset = compat.unpack_I8(string.sub(block, 17))

        local tileData, _ = webtiles.readTileData(x, y, z, fileAccess)

        assert(tileData == tostring(tonumber(offset)),
            "expected: " .. tostring(tonumber(offset)) .. ", actual: " .. tileData)
    end
    f:close()
end

runTest("empty.index", "empty_basic.wtiles")
runTest("empty.index", "empty_plain.wtiles")
runTest("empty.index", "empty_sparse.wtiles")
-- small tests do not work with lua5.1
runTest("small.index", "small_basic.wtiles")
runTest("small.index", "small_plain.wtiles")
runTest("small.index", "small_sparse.wtiles")
-- runTest("medium.index", "medium_basic.wtiles")
-- runTest("medium.index", "medium_plain.wtiles")
-- runTest("medium.index", "medium_sparse.wtiles")
runTest("data42.index", "data42_plain.wtiles")
runTest("data42.index", "data42_sparse.wtiles")
runTest("full5.index", "full5_sparse.wtiles")
runTest("z20.index",   "z20_sparse.wtiles")
print("done!")

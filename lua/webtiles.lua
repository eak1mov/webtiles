local compat = require("webtiles.compat")
local bit = compat.bit
local flatbuffers = require("flatbuffers")

local FileHeader = require("webtiles.fbs.FileHeader")
local BlockType = require("webtiles.fbs.BlockType")
local DenseLocations = require("webtiles.fbs.DenseLocations")
local Header = require("webtiles.fbs.Header")
local HeaderSignature = require("webtiles.fbs.HeaderSignature")
local HeaderSize = require("webtiles.fbs.HeaderSize")
local HeaderVersion = require("webtiles.fbs.HeaderVersion")
local IndexFormat = require("webtiles.fbs.IndexFormat")
local IndexHeader = require("webtiles.fbs.IndexHeader")
local IndexMagic = require("webtiles.fbs.IndexMagic")
local LinkItem = require("webtiles.fbs.LinkItem")
local LocationItem = require("webtiles.fbs.LocationItem")
local Location = require("webtiles.fbs.Location")
local SparseBlock = require("webtiles.fbs.SparseBlock")
local SparseLocations = require("webtiles.fbs.SparseLocations")

--------------------------------------------------------------------------------
-- common
--------------------------------------------------------------------------------

local PACKED_LOCATION_SIZE = 8
local ERROR_INVALID_DATASET = setmetatable({}, {__tostring = function() return "Invalid dataset" end})
local ERROR_INVALID_REQUEST = setmetatable({}, {__tostring = function() return "Invalid request" end})
local ERROR_INVALID_FILE_FORMAT = setmetatable({}, {__tostring = function() return "Invalid file format" end})
local ERROR_INVALID_VERSION = setmetatable({}, {__tostring = function() return "Invalid version" end})

local function unpackLocation(location)
    local offset = tonumber(bit.band(location, 0xFFFFFFFFFF)) -- 2^40-1
    local size = tonumber(bit.rshift(location, 40))
    return {offset = offset, size = size}
end

local function unpackLocationBytes(locationData)
    return unpackLocation(compat.unpack_I8(locationData))
end

local function unpackLocationFbs(locationFbs)
    return unpackLocation(locationFbs.view:Get(flatbuffers.N.Uint64, locationFbs.view.pos))
end

local function blockLevelIdx(blockLevels, zoom)
    for i, z in ipairs(blockLevels) do
        if z > zoom then
            return i - 1
        end
    end
    return nil
end

local function interleave(x)
    x = bit.band(bit.bor(x, bit.lshift(x, 8)), 0x00FF00FF)
    x = bit.band(bit.bor(x, bit.lshift(x, 4)), 0x0F0F0F0F)
    x = bit.band(bit.bor(x, bit.lshift(x, 2)), 0x33333333)
    x = bit.band(bit.bor(x, bit.lshift(x, 1)), 0x55555555)
    return x
end

local function deinterleave(x)
    x = bit.band(x, 0x55555555)
    x = bit.band(bit.bor(x, bit.rshift(x, 1)), 0x33333333)
    x = bit.band(bit.bor(x, bit.rshift(x, 2)), 0x0F0F0F0F)
    x = bit.band(bit.bor(x, bit.rshift(x, 4)), 0x00FF00FF)
    x = bit.band(bit.bor(x, bit.rshift(x, 8)), 0x0000FFFF)
    return x
end

local function encodeTileId(tileId)
    return tonumber(bit.bor(interleave(tileId.x), bit.lshift(interleave(tileId.y), 1)))
end

local function decodeTileId(tileCode, z)
    return {
        x = deinterleave(tileCode),
        y = deinterleave(bit.rshift(tileCode, 1)),
        z = z,
    }
end

--------------------------------------------------------------------------------
-- plain format
--------------------------------------------------------------------------------

local function calcBlockSize(zoomCount)
    -- 4^0 + 4^1 + ... + 4^(zoomCount-1)
    return math.floor(((4 ^ zoomCount) - 1) / 3)
end

local function queryPlainBlock(tileId, blockLevels)
    local blockIdx = blockLevelIdx(blockLevels, tileId.z)
    local blockZ = blockLevels[blockIdx]
    local innerZ = tileId.z - blockZ
    local innerZCount = blockLevels[blockIdx + 1] - blockLevels[blockIdx]

    local blockTileId = {
        x = bit.rshift(tileId.x, innerZ),
        y = bit.rshift(tileId.y, innerZ),
        z = tileId.z - innerZ,
    }
    local innerTileId = {
        x = bit.band(tileId.x, bit.lshift(1, innerZ) - 1),
        y = bit.band(tileId.y, bit.lshift(1, innerZ) - 1),
        z = innerZ,
    }

    local blockCode = encodeTileId(blockTileId)
    local blockSize = calcBlockSize(innerZCount)
    local blockOffset = calcBlockSize(blockZ) + blockCode * blockSize

    local innerCode = encodeTileId(innerTileId)
    local innerSize = 1
    local innerOffset = calcBlockSize(innerZ) + innerCode * innerSize

    local blockLocation = {offset = blockOffset * PACKED_LOCATION_SIZE, size = blockSize * PACKED_LOCATION_SIZE}
    local innerLocation = {offset = innerOffset * PACKED_LOCATION_SIZE, size = innerSize * PACKED_LOCATION_SIZE}
    return blockLocation, innerLocation
end

local function queryPlainFormat(tileId, blockLevels, indexAccess)
    local blockLocation, innerLocation = queryPlainBlock(tileId, blockLevels)

    local indexData = indexAccess(blockLocation.offset, blockLocation.size)

    local tileLocationData = string.sub(indexData, innerLocation.offset + 1, innerLocation.offset + innerLocation.size)
    local tileLocation = unpackLocationBytes(tileLocationData)

    return tileLocation
end

--------------------------------------------------------------------------------
-- sparse format
--------------------------------------------------------------------------------

local function binarySearch(n, cmp)
    local l = 1
    local r = n

    while l <= r do
        local mid = math.floor((l + r) / 2)

        local cmpValue = cmp(mid)
        if cmpValue == 0 then
            return mid
        elseif cmpValue > 0 then
            l = mid + 1
        else
            r = mid - 1
        end
    end

    return nil
end

local function parent(tileId)
    return {
        x = bit.rshift(tileId.x, 1),
        y = bit.rshift(tileId.y, 1),
        z = tileId.z - 1,
    }
end

local function changeRoot(tile, root, newRoot)
    local zDiff = tile.z - root.z
    local mask = bit.lshift(1, zDiff) - 1
    return {
        x = bit.lshift(newRoot.x, zDiff) + bit.band(tile.x, mask),
        y = bit.lshift(newRoot.y, zDiff) + bit.band(tile.y, mask),
        z = newRoot.z + zDiff,
    }
end

local function findTile(block, tileId)
    assert(tileId.z <= block:SparseLocationsLength(), ERROR_INVALID_DATASET)
    local locations = block:SparseLocations(tileId.z + 1)
    local tileCode = encodeTileId(tileId)

    local idx = binarySearch(locations:TilesLength(), function (i)
        return tileCode - locations:Tiles(i):TileCode()
    end)

    if idx == nil then
        return nil
    end

    return locations:Tiles(idx)
end

local function findLink(block, tileId)
    assert(tileId.z <= block:SparseLocationsLength(), ERROR_INVALID_DATASET)
    local locations = block:SparseLocations(tileId.z + 1)
    local tileCode = encodeTileId(tileId)

    local idx = binarySearch(locations:LinksLength(), function (i)
        return tileCode - locations:Links(i):TileCode()
    end)

    if idx == nil then
        return nil
    end

    return locations:Links(idx)
end

local function resolveLink(block, tileId)
    local link = findLink(block, tileId)
    return decodeTileId(link:LinkCode(), tileId.z)
end

local function querySparseLocations(block, tileId)
    while findTile(block, tileId) == nil do
        local pTileId = tileId
        while findTile(block, pTileId) == nil and findLink(block, pTileId) == nil do
            pTileId = parent(pTileId)
        end
        if findTile(block, pTileId) == nil then
            tileId = changeRoot(tileId, pTileId, resolveLink(block, pTileId))
        end
    end
    local tile = findTile(block, tileId)
    return tile:Location(Location.New())
end

local function queryDenseLocations(block, tileId)
    local tileCode = encodeTileId(tileId)

    local denseLocations = block:DenseLocations(tileId.z + 1)
    assert(denseLocations ~= nil, ERROR_INVALID_DATASET)

    local location = denseLocations:Locations(tileCode + 1)
    assert(location ~= nil, ERROR_INVALID_DATASET)

    return location
end

local function queryBlock(block, tileId)
    local blockType = block:BlockType()
    if blockType == BlockType.Dense then
        return queryDenseLocations(block, tileId)
    elseif blockType == BlockType.Sparse then
        return querySparseLocations(block, tileId)
    else
        error(ERROR_INVALID_DATASET)
    end
end

local function querySparseBlock(tileId, blockLevels, blockIdx, blockData)
    local tileZ = tileId.z
    local blockZ = blockLevels[blockIdx]
    local nextBlockZ = blockLevels[blockIdx + 1]

    local nextZ = math.min(nextBlockZ, tileZ)
    local nextSize = nextZ - blockZ
    local nextMask = bit.lshift(1, nextSize) - 1

    local innerTileId = {
        x = bit.band(bit.rshift(tileId.x, tileZ - nextZ), nextMask),
        y = bit.band(bit.rshift(tileId.y, tileZ - nextZ), nextMask),
        z = nextSize,
    }

    local block = SparseBlock.GetRootAsSparseBlock(blockData, 0)

    return unpackLocationFbs(queryBlock(block, innerTileId))
end

local function querySparseFormat(tileId, blockLevels, rootLocation, indexAccess)
    local location = rootLocation

    local maxBlockIdx = blockLevelIdx(blockLevels, tileId.z)
    for blockIdx = 1, maxBlockIdx do
        if location.size == 0 then
            return location
        end
        local blockData = indexAccess(location.offset, location.size)
        location = querySparseBlock(tileId, blockLevels, blockIdx, blockData)
    end

    return location
end

--------------------------------------------------------------------------------
-- webtiles
--------------------------------------------------------------------------------

local function readTileLocation(x, y, z, fileAccess)
    local headerData = fileAccess(0, HeaderSize.Extended)

    local header = Header.New()
    header:Init(headerData, 0)
    local fileHeader = header:FileHeader(FileHeader.New())
    local indexHeader = header:IndexHeader(IndexHeader.New())

    local headerSignature = fileHeader:Signature()
    if tonumber(headerSignature) ~= HeaderSignature.Value then
        error(ERROR_INVALID_FILE_FORMAT)
    end
    local headerVersion = fileHeader:Version()
    if tonumber(headerVersion) ~= HeaderVersion.V02 then
        error(ERROR_INVALID_VERSION)
    end

    local extendedBegin = fileHeader:ExtendedOffset() + 1
    local extendedEnd = fileHeader:ExtendedOffset() + fileHeader:ExtendedSize()
    local extendedHeader = string.sub(headerData, tonumber(extendedBegin), tonumber(extendedEnd))

    if z > indexHeader:MaxZoom() then
        error(ERROR_INVALID_REQUEST)
    end
    local blockLevelsMask = indexHeader:BlockLevelsMask()

    local blockLevels = {}
    local blockLevelsCount = 0
    for i = 0, 30 do
        if bit.band(blockLevelsMask, bit.lshift(1, i)) ~= 0 then
            blockLevelsCount = blockLevelsCount + 1
            blockLevels[blockLevelsCount] = i
        end
    end

    if blockLevelsCount == 0 then
        return {offset = 0, size = 0}, extendedHeader
    end

    local tileId = {x = x, y = y, z = z}
    local rootOffset = indexHeader:RootOffset()
    local rootSize = indexHeader:RootSize()
    local rootLocation = {offset = tonumber(rootOffset), size = tonumber(rootSize)}
    local indexOffset = fileHeader:IndexOffset()
    local indexAccess = function (offset, size)
        return fileAccess(tonumber(indexOffset) + offset, size)
    end

    local indexFormat = indexHeader:Format()

    local tileLocation = nil
    if indexFormat == IndexFormat.Plain or indexFormat == IndexFormat.BasicPlain then
        tileLocation = queryPlainFormat(tileId, blockLevels, indexAccess)
    elseif indexFormat == IndexFormat.Sparse then
        tileLocation = querySparseFormat(tileId, blockLevels, rootLocation, indexAccess)
    else
        error(ERROR_INVALID_DATASET)
    end

    local dataOffset = fileHeader:DataOffset()
    tileLocation.offset = tileLocation.offset + tonumber(dataOffset)

    return tileLocation, extendedHeader
end

local function readTileData(x, y, z, fileAccess)
    local tileLocation, extendedHeader = readTileLocation(x, y, z, fileAccess)
    if tileLocation.size == 0 then
        return '', extendedHeader
    end
    local tileData = fileAccess(tileLocation.offset, tileLocation.size)
    return tileData, extendedHeader
end

-- TODO(eak1mov): add Reader

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

local m = {}
m.readTileData = readTileData
m.readTileLocation = readTileLocation
m.ERROR_INVALID_DATASET = ERROR_INVALID_DATASET
m.ERROR_INVALID_REQUEST = ERROR_INVALID_REQUEST
m.ERROR_INVALID_FILE_FORMAT = ERROR_INVALID_FILE_FORMAT
m.ERROR_INVALID_VERSION = ERROR_INVALID_VERSION
return m

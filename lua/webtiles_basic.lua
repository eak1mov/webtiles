local bit = require("bit")
local ffi = require("ffi")

local FileHeader = require("webtiles.fbs.FileHeader")
local Header = require("webtiles.fbs.Header")
local HeaderSignature = require("webtiles.fbs.HeaderSignature")
local HeaderSize = require("webtiles.fbs.HeaderSize")
local HeaderVersion = require("webtiles.fbs.HeaderVersion")
local IndexFormat = require("webtiles.fbs.IndexFormat")
local IndexHeader = require("webtiles.fbs.IndexHeader")

local PACKED_LOCATION_SIZE = 8

local function unpackLocationBytes(locationData)
    local location = ffi.cast("uint64_t*", locationData)[0]
    local offset = tonumber(bit.band(location, 0xFFFFFFFFFF)) -- 2^40-1
    local size = tonumber(bit.rshift(location, 40))
    return {offset = offset, size = size}
end

local function interleave(x)
    x = bit.band(bit.bor(x, bit.lshift(x, 8)), 0x00FF00FF)
    x = bit.band(bit.bor(x, bit.lshift(x, 4)), 0x0F0F0F0F)
    x = bit.band(bit.bor(x, bit.lshift(x, 2)), 0x33333333)
    x = bit.band(bit.bor(x, bit.lshift(x, 1)), 0x55555555)
    return x
end

local function encodeTileId(x, y)
    return tonumber(bit.bor(interleave(x), bit.lshift(interleave(y), 1)))
end

local function calcBlockSize(zoomCount)
    return math.floor(((4 ^ zoomCount) - 1) / 3)
end

local function readTileLocation(x, y, z, fileAccess)
    local headerData = fileAccess(0, HeaderSize.Regular)

    local header = Header.New()
    header:Init(headerData, 0)
    local fileHeader = header:FileHeader(FileHeader.New())
    local indexHeader = header:IndexHeader(IndexHeader.New())

    assert(tonumber(fileHeader:Signature()) == HeaderSignature.Value)
    assert(tonumber(fileHeader:Version()) == HeaderVersion.V02)
    assert(tonumber(indexHeader:Format()) == IndexFormat.BasicPlain)

    assert(z <= tonumber(indexHeader:MaxZoom()))
    assert(tonumber(indexHeader:BlockLevelsMask()) ~= 0)

    local tileCode = encodeTileId(x, y)
    local blockOffset = calcBlockSize(z)
    local indexOffset = tonumber(fileHeader:IndexOffset())
    local tileLocationOffset = indexOffset + (blockOffset + tileCode) * PACKED_LOCATION_SIZE

    local tileLocationData = fileAccess(tileLocationOffset, PACKED_LOCATION_SIZE)
    local tileLocation = unpackLocationBytes(tileLocationData)

    tileLocation.offset = tileLocation.offset + tonumber(fileHeader:DataOffset())

    return tileLocation
end

local function readTileData(x, y, z, fileAccess)
    local tileLocation = readTileLocation(x, y, z, fileAccess)
    if tileLocation.size == 0 then
        return ''
    end
    local tileData = fileAccess(tileLocation.offset, tileLocation.size)
    return tileData
end

local m = {}
m.readTileLocation = readTileLocation
m.readTileData = readTileData
return m

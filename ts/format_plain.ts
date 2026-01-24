import * as ic from "./common";

function calcBlockSize(zoomCount: number): number {
  // = 4^0 + 4^1 + ... + 4^(zoomCount-1)
  return Math.floor(((1 << (2 * zoomCount)) - 1) / 3);
}

export function queryPlainBlock(tileId: ic.TileId, blockLevels: ic.ZoomLevels): [ic.Location, ic.Location] {
  const blockIdx = ic.blockLevelIdx(blockLevels, tileId.z);
  const blockZ = blockLevels[blockIdx];
  const innerZ = tileId.z - blockZ;
  const innerZCount = blockLevels[blockIdx + 1] - blockLevels[blockIdx];

  const blockTileId: ic.TileId = {
    x: tileId.x >> innerZ,
    y: tileId.y >> innerZ,
    z: tileId.z - innerZ,
  };
  const innerTileId: ic.TileId = {
    x: tileId.x & ((1 << innerZ) - 1),
    y: tileId.y & ((1 << innerZ) - 1),
    z: innerZ,
  };

  const blockCode = ic.encodeTileId(blockTileId);
  const blockSize = calcBlockSize(innerZCount);
  const blockOffset = calcBlockSize(blockZ) + blockCode * blockSize;

  const innerCode = ic.encodeTileId(innerTileId);
  const innerSize = 1;
  const innerOffset = calcBlockSize(innerZ) + innerCode * innerSize;

  const blockLocation: ic.Location = {
    offset: blockOffset * ic.PACKED_LOCATION_SIZE,
    size: blockSize * ic.PACKED_LOCATION_SIZE,
  };
  const innerLocation: ic.Location = {
    offset: innerOffset * ic.PACKED_LOCATION_SIZE,
    size: innerSize * ic.PACKED_LOCATION_SIZE,
  };
  return [blockLocation, innerLocation];
}

export async function queryPlainFormat(
  tileId: ic.TileId,
  blockLevels: ic.ZoomLevels,
  indexAccess: ic.FileAccessFunc,
): Promise<ic.Location> {
  const [blockLocation, innerLocation] = queryPlainBlock(tileId, blockLevels);

  const indexData: ArrayBuffer = await indexAccess(blockLocation.offset, blockLocation.size);

  const tileLocationData = new DataView(indexData, innerLocation.offset, innerLocation.size);
  const tileLocation: ic.Location = ic.unpackLocation(tileLocationData);

  return tileLocation;
}

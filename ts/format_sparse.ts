import * as fbs from "./fbs";
import * as flatbuffers from "flatbuffers";
import * as ic from "./common";

// We assume all datasets available to the server are valid (they already have
// valid signature and version), so we throw in case of any error in data.
function check(condition: boolean) {
  if (!condition) {
    throw new ic.InvalidDatasetError();
  }
}

function parent(tileId: ic.TileId): ic.TileId {
  check(tileId.z > 0);
  return {
    x: tileId.x >> 1,
    y: tileId.y >> 1,
    z: tileId.z - 1,
  };
}

// Returns a tile in the `newRoot` subtree with the same path as `tile` in the `root` subtree.
// Returned value will have higher bits from `newRoot`, and lower bits from `tile`:
// bits             <- higher, lower ->
// root:            [RRRRRRRR]
// newRoot:         [NNNNNNNN]
// tile:            [RRRRRRRRTTTTTTTT]
// returned TileId: [NNNNNNNNTTTTTTTT]
function changeRoot(tile: ic.TileId, root: ic.TileId, newRoot: ic.TileId): ic.TileId {
  // `root` and `newRoot` must be on the same z level
  check(root.z === newRoot.z);
  // `tile` must be in the `root` subtree
  check(root.z <= tile.z);

  const zDiff = tile.z - root.z;
  const mask = (1 << zDiff) - 1;

  // `tile` must be in the `root` subtree (they have the same higher bits)
  check(root.x === (tile.x >> zDiff));
  check(root.y === (tile.y >> zDiff));

  return {
    x: (newRoot.x << zDiff) + (tile.x & mask),
    y: (newRoot.y << zDiff) + (tile.y & mask),
    z: newRoot.z + zDiff,
  };
}

function unpackLocationFbs(location: fbs.Location): ic.Location {
  return ic.unpackLocation(new DataView(location.bb!.bytes().buffer, location.bb_pos));
}

function binarySearch(n: number, cmp: (i: number) => number): number | null {
  let i = 0;
  let j = n;
  while (i < j) {
    const h = Math.floor((i + j) / 2);
    if (cmp(h) > 0) {
      i = h + 1;
    } else {
      j = h;
    }
  }
  return (i < n && cmp(i) === 0) ? i : null;
}

function findTile(block: fbs.SparseBlock, tileId: ic.TileId): fbs.LocationItem | null {
  const locations = block.sparseLocations(tileId.z)!;
  const tileCode = ic.encodeTileId(tileId);

  const idx = binarySearch(locations.tilesLength(), (i: number): number => {
    return tileCode - locations.tiles(i)!.tileCode();
  });

  return (idx === null) ? null : locations.tiles(idx);
}

function findLink(block: fbs.SparseBlock, tileId: ic.TileId): fbs.LinkItem | null {
  const locations = block.sparseLocations(tileId.z)!;
  const tileCode = ic.encodeTileId(tileId);

  const idx = binarySearch(locations.linksLength(), (i: number): number => {
    return tileCode - locations.links(i)!.tileCode();
  });

  return (idx === null) ? null : locations.links(idx);
}

function resolveLink(block: fbs.SparseBlock, tileId: ic.TileId): ic.TileId {
  return ic.decodeTileId(findLink(block, tileId)!.linkCode(), tileId.z);
}

function querySparseLocations(block: fbs.SparseBlock, tileId: ic.TileId): fbs.Location {
  while (findTile(block, tileId) === null) {
    let pTileId = tileId;
    while (findTile(block, pTileId) === null && findLink(block, pTileId) === null) {
      pTileId = parent(pTileId);
    }
    if (findTile(block, pTileId) === null) {
      tileId = changeRoot(tileId, pTileId, resolveLink(block, pTileId));
    }
  }
  return findTile(block, tileId)!.location()!;
}

function queryDenseLocations(block: fbs.SparseBlock, tileId: ic.TileId): fbs.Location {
  const locations = block.denseLocations(tileId.z)!;
  const tileCode = ic.encodeTileId(tileId);

  return locations.locations(tileCode)!;
}

function queryBlock(block: fbs.SparseBlock, tileId: ic.TileId): fbs.Location {
  switch (block.blockType()) {
    case fbs.BlockType.Dense:
      return queryDenseLocations(block, tileId);
    case fbs.BlockType.Sparse:
      return querySparseLocations(block, tileId);
    default:
      throw new ic.InvalidDatasetError();
  }
}

export function querySparseBlock(
  tileId: ic.TileId,
  blockLevels: ic.ZoomLevels,
  blockIdx: number,
  blockData: ArrayBuffer,
): ic.Location {
  const tileZ = tileId.z;
  const blockZ = blockLevels[blockIdx];
  const nextBlockZ = blockLevels[blockIdx + 1];

  const nextZ = Math.min(nextBlockZ, tileZ);
  const nextSize = nextZ - blockZ;
  const nextMask = (1 << nextSize) - 1;

  // smaller zoom levels correspond to top bits of x/y coordinates
  // top block = top bits of coordinate, bottom block = bottom bits of coordinate
  const innerTileId: ic.TileId = {
    x: (tileId.x >> (tileZ - nextZ)) & nextMask,
    y: (tileId.y >> (tileZ - nextZ)) & nextMask,
    z: nextSize,
  };

  const blockBuffer = new flatbuffers.ByteBuffer(new Uint8Array(blockData));
  const block = fbs.SparseBlock.getRootAsSparseBlock(blockBuffer);

  return unpackLocationFbs(queryBlock(block, innerTileId));
}

export async function querySparseFormat(
  tileId: ic.TileId,
  blockLevels: ic.ZoomLevels,
  rootLocation: ic.Location,
  indexAccess: ic.FileAccessFunc,
): Promise<ic.Location> {
  let location: ic.Location = rootLocation;

  const maxBlockIdx: number = ic.blockLevelIdx(blockLevels, tileId.z);
  for (let blockIdx = 0; blockIdx <= maxBlockIdx; blockIdx++) {
    if (location.size === 0) {
      return location;
    }
    const blockData = await indexAccess(location.offset, location.size);
    location = querySparseBlock(tileId, blockLevels, blockIdx, blockData);
  }

  return location;
}

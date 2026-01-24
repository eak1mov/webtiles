export interface TileId {
  x: number;
  y: number;
  z: number;
}

function interleave(x: number): number {
  x = (x | (x << 8)) & 0x00FF00FF;
  x = (x | (x << 4)) & 0x0F0F0F0F;
  x = (x | (x << 2)) & 0x33333333;
  x = (x | (x << 1)) & 0x55555555;
  return x;
}

function deinterleave(x: number): number {
  x = x & 0x55555555;
  x = (x | (x >> 1)) & 0x33333333;
  x = (x | (x >> 2)) & 0x0F0F0F0F;
  x = (x | (x >> 4)) & 0x00FF00FF;
  x = (x | (x >> 8)) & 0x0000FFFF;
  return x;
}

export function encodeTileId(tileId: TileId): number {
  return interleave(tileId.x) | (interleave(tileId.y) << 1);
}

export function decodeTileId(tileCode: number, z: number): TileId {
  return {
    x: deinterleave(tileCode),
    y: deinterleave(tileCode >> 1),
    z: z,
  };
}

export const MAX_ZOOM = 24;

export type ZoomLevels = number[];

export function blockLevelIdx(blockLevels: ZoomLevels, zoom: number): number {
  return blockLevels.findIndex((zlevel) => zlevel > zoom) - 1;
}

export interface Location {
  offset: number;
  size: number;
}

export const PACKED_LOCATION_SIZE = 8;

export function unpackLocation(data: DataView): Location {
  const packedLocation = data.getBigUint64(0, true);
  return {
    offset: Number(packedLocation & ((1n << 40n) - 1n)),
    size: Number(packedLocation >> 40n),
  };
}

export type FileAccessFunc = (offset: number, size: number) => Promise<ArrayBuffer>;

export class WebtilesError extends Error { }
export class InvalidDatasetError extends WebtilesError {
  public constructor() { super("Invalid dataset"); }
}
export class InvalidRequestError extends WebtilesError {
  public constructor() { super("Invalid tile request"); }
}
export class InvalidFileFormatError extends WebtilesError {
  public constructor() { super("Invalid file format"); }
}
export class InvalidVersionError extends WebtilesError {
  public constructor() { super("Invalid version"); }
}

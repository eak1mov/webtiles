import { expect, test } from "@jest/globals";

import * as ic from "./common";

test("decodeEncode", () => {
  for (let z = 0; z < 5; z++) {
    for (let tileCode = 0; tileCode < (1 << (2 * z)); tileCode++) {
      expect(ic.encodeTileId(ic.decodeTileId(tileCode, z))).toBe(tileCode);
    }
  }
});

test("blockLevelIdx", () => {
  expect(ic.blockLevelIdx([0, 10, 20], 0)).toBe(0);
  expect(ic.blockLevelIdx([0, 10, 20], 1)).toBe(0);
  expect(ic.blockLevelIdx([0, 10, 20], 9)).toBe(0);
  expect(ic.blockLevelIdx([0, 10, 20], 10)).toBe(1);
  expect(ic.blockLevelIdx([0, 10, 20], 11)).toBe(1);
  expect(ic.blockLevelIdx([0, 10, 20], 19)).toBe(1);
});

test("unpackLocation", () => {
  const location = ic.unpackLocation(
    new DataView(Uint8Array.from([1, 0, 0, 0, 0, 1, 0, 0]).buffer),
  );
  expect(location.offset).toBe(1);
  expect(location.size).toBe(1);
});

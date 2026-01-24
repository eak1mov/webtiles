import { expect, test } from "@jest/globals";
import fs from "node:fs";

import { Reader } from "./reader";

// run `npm run build_testdata` to prepare test data
const TESTDATA_PATH = "bazel-bin/testdata/";

interface IndexItem {
  x: number;
  y: number;
  z: number;
  size: number;
  offset: number;
}

async function runTest(indexFileName: string, wtFileName: string) {
  const indexItemsFd = fs.openSync(TESTDATA_PATH + indexFileName, "r");
  const wtFd = fs.openSync(TESTDATA_PATH + wtFileName, "r");

  const indexItems: IndexItem[] = [];
  const indexItemData = new DataView(new ArrayBuffer(24));
  while (fs.readSync(indexItemsFd, indexItemData, 0, 24, null)) {
    indexItems.push({
      x: indexItemData.getUint32(0, true),
      y: indexItemData.getUint32(4, true),
      z: indexItemData.getUint32(8, true),
      size: indexItemData.getUint32(12, true),
      offset: Number(indexItemData.getBigUint64(16, true)),
    });
  }

  const fileAccess = async (offset: number, size: number): Promise<ArrayBuffer> => {
    const buffer = new ArrayBuffer(size);
    fs.readSync(wtFd, new DataView(buffer), 0, size, offset);
    return buffer;
  };

  const reader: Reader = await Reader.create(fileAccess);

  await expect(reader.tileData(0, 0, 0)).resolves.not.toThrow();

  for (const item of indexItems) {
    const tileData = await reader.tileData(item.x, item.y, item.z);
    expect(new TextDecoder().decode(tileData)).toBe(String(item.offset));
  }
}

test("empty_basic", async () => { await runTest("empty.index", "empty_basic.wtiles"); });
test("empty_plain", async () => { await runTest("empty.index", "empty_plain.wtiles"); });
test("empty_sparse", async () => { await runTest("empty.index", "empty_sparse.wtiles"); });
test("small_basic", async () => { await runTest("small.index", "small_basic.wtiles"); });
test("small_plain", async () => { await runTest("small.index", "small_plain.wtiles"); });
test("small_sparse", async () => { await runTest("small.index", "small_sparse.wtiles"); });
test("full5_sparse", async () => { await runTest("full5.index", "full5_sparse.wtiles"); });
test("z20_sparse", async () => { await runTest("z20.index", "z20_sparse.wtiles"); });

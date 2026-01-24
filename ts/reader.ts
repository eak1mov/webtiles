import * as fbs from "./fbs";
import * as flatbuffers from "flatbuffers";
import * as ic from "./common";
import { queryPlainFormat } from "./format_plain";
import { querySparseFormat } from "./format_sparse";

export class Reader {
  private readonly fileAccess: ic.FileAccessFunc;
  private readonly header: fbs.Header;
  private readonly extendedHeaderData: ArrayBuffer;

  private constructor(fileAccess: ic.FileAccessFunc, headerData: ArrayBuffer) {
    this.fileAccess = async (offset: number, size: number): Promise<ArrayBuffer> => {
      return size === 0 ? new ArrayBuffer(0) : fileAccess(offset, size);
    };

    const headerBuffer = new flatbuffers.ByteBuffer(new Uint8Array(headerData));
    this.header = new fbs.Header().__init(0, headerBuffer);

    const fileHeader: fbs.FileHeader = this.header.fileHeader()!;
    if (fileHeader.signature() !== BigInt(fbs.HeaderSignature.Value)) {
      throw new ic.InvalidFileFormatError();
    }
    if (fileHeader.version() > Math.max(...Object.values(fbs.HeaderVersion).map(Number))) {
      throw new ic.InvalidVersionError();
    }

    const extendedBegin = Number(fileHeader.extendedOffset());
    const extendedEnd = extendedBegin + Number(fileHeader.extendedSize());
    this.extendedHeaderData = headerData.slice(extendedBegin, extendedEnd);
  }

  public static async create(fileAccess: ic.FileAccessFunc): Promise<Reader> {
    const headerData: ArrayBuffer = await fileAccess(0, Number(fbs.HeaderSize.Extended));
    return new Reader(fileAccess, headerData);
  }

  public async tileData(x: number, y: number, z: number): Promise<ArrayBuffer> {
    const fileHeader: fbs.FileHeader = this.header.fileHeader()!;
    const indexHeader: fbs.IndexHeader = this.header.indexHeader()!;

    if (z > indexHeader.maxZoom()) {
      throw new ic.InvalidRequestError();
    }

    const blockLevelsMask = Number(indexHeader.blockLevelsMask());
    const blockLevels: number[] = [];
    for (let zoom = 0; zoom <= ic.MAX_ZOOM; zoom++) {
      if (blockLevelsMask & (1 << zoom)) {
        blockLevels.push(zoom);
      }
    }

    if (!blockLevels.length) {
      return new ArrayBuffer(0);
    }

    const tileId: ic.TileId = { x, y, z };
    const rootLocation: ic.Location = {
      offset: Number(indexHeader.rootOffset()),
      size: Number(indexHeader.rootSize()),
    };
    const indexAccess: ic.FileAccessFunc = async (offset: number, size: number): Promise<ArrayBuffer> => {
      return this.fileAccess(Number(fileHeader.indexOffset()) + offset, size);
    };

    const tileLocation: ic.Location = await (async () => {
      switch (indexHeader.format()) {
        case BigInt(fbs.IndexFormat.BasicPlain):
        case BigInt(fbs.IndexFormat.Plain):
          return queryPlainFormat(tileId, blockLevels, indexAccess);
        case BigInt(fbs.IndexFormat.Sparse):
          return querySparseFormat(tileId, blockLevels, rootLocation, indexAccess);
        default:
          throw new ic.InvalidDatasetError();
      }
    })();

    return this.fileAccess(tileLocation.offset, tileLocation.size);
  }

  public async metadata(): Promise<ArrayBuffer> {
    const fileHeader: fbs.FileHeader = this.header.fileHeader()!;

    return this.fileAccess(
      Number(fileHeader.metadataOffset()),
      Number(fileHeader.metadataSize()),
    );
  }

  public extendedHeader(): ArrayBuffer {
    return this.extendedHeaderData;
  }
}

import * as flatbuffers from "flatbuffers";
import { Reader } from "./reader";
import { ResponseParams } from "./fbs/response-params";

// maplibregl custom protocol prefix, usage:
// {url: "webtiles://http://my_cloud/my_bucket/example.wtiles"}
// {url: "webtiles:////my_cloud/my_bucket/example.wtiles"}
// {url: "webtiles:///example.wtiles"}
const PREFIX = "webtiles://";

export interface ProtocolParams {
  fetchRequest: (
    url: string,
    headers: Record<string, string>,
    signal: any, // eslint-disable-line @typescript-eslint/no-explicit-any
  ) => Promise<ArrayBuffer>;

  contentDecoder?: (
    buffer: ArrayBuffer,
    params: ResponseParams,
  ) => Promise<ArrayBuffer>;
}

export function maplibregl(params: ProtocolParams) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return async (req: any, abortController: any) => {
    if (!req.url.startsWith(PREFIX)) {
      throw new Error("Invalid protocol");
    }

    if (req.type === "json") {
      return { data: { tiles: [`${req.url}#{x}_{y}_{z}`] } };
    }

    const [tilesetUrl, coords] = req.url.substring(PREFIX.length).split("#");
    const [x, y, z] = coords.split("_").map(Number);

    const reader = await Reader.create(async (offset, size) => {
      const data = await params.fetchRequest(
        tilesetUrl,
        { "Range": `bytes=${offset}-${offset + size - 1}` },
        abortController.signal,
      );
      if (data.byteLength !== size) {
        throw new Error("Invalid source");
      }
      return data;
    });

    let tileData = await reader.tileData(x, y, z);

    if (params.contentDecoder) {
      const headerData = reader.extendedHeader();
      const headerBuffer = new flatbuffers.ByteBuffer(new Uint8Array(headerData));
      const responseParams = ResponseParams.getRootAsResponseParams(headerBuffer);
      tileData = await params.contentDecoder(tileData, responseParams);
    }

    return { data: tileData };
  };
}

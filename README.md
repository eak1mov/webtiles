# WebTiles: A Modern Tile Storage Format

[![License](https://img.shields.io/github/license/eak1mov/webtiles)](https://github.com/eak1mov/webtiles/blob/main/LICENSE)
[![NPM Package](https://img.shields.io/npm/v/webtiles)](https://www.npmjs.com/package/webtiles)
[![GitHub Repo](https://img.shields.io/github/stars/eak1mov/webtiles)](https://github.com/eak1mov/webtiles)

WebTiles is a high-performance file format designed for storing and serving large collections of map tiles (raster or vector tiles).  
It's a single-file container that enables extremely fast random access, overcoming some limitations of formats like PMTiles, MBTiles and file-per-tile storage.  
The format is defined by FlatBuffers schema for portability and provides C++ and Lua implementations.

## Features

- **Single-File Container**: Store all tiles in one file. Easy to manage, copy, and distribute.
- **Fast Random Access**: Designed for high-concurrency server environments (50k+ RPS).
- **Tile Deduplication**: Identical tiles are stored only once, saving significant space for datasets with repeating patterns (like empty ocean tiles).
- **Efficient Storage**: Multiple index formats (Plain, Sparse) optimized for different data distributions.
- **Portable**: The core format is defined by a language-agnostic [FlatBuffers](https://flatbuffers.dev/) schema.
- **Extensible**: Support for custom metadata sections.

## Format Overview

<!--
TODO(eak1mov): add link to the paper: https://habr.com/ru/companies/yandex/articles/1013916/
TODO(eak1mov): add `Metadata Section`
-->

A WebTiles file consists of three main sections:

- **Header**: A small, fixed-size section at the beginning of the file. It contains the magic number, version, and offsets/sizes for other sections.
- **Data Section**: A contiguous blob of deduplicated tile data. Each unique tile is stored here sequentially.
- **Index Section**: This section contains the logic to map a `(z, x, y)` tile coordinate to its location and size within the Data Section. The structure of this section depends on the `IndexFormat` chosen during creation.

## Getting Started

### Prerequisites

- [Bazel](https://bazel.build/install) build system.
- C++20 compatible toolchain.
- Dependencies are managed by Bazel (abseil, flatbuffers).

### Building

```bash
# Clone the repository
git clone https://github.com/eak1mov/webtiles.git
cd webtiles

# Build everything
bazel build //...

# Run tests
bazel test //...
bazel run //webtiles:tests
```

### Command Line Tools (examples)

```bash
# Build all converters
bazel build //converter:all

# Convert mbtiles to webtiles:
bazel-bin/converter/import_mbtiles --input_path=input.mbtiles --output_path=output.wtiles

# Convert webtiles to mbtiles:
bazel-bin/converter/export_mbtiles --input_path=input.wtiles --output_path=output.mbtiles

# Export webtiles file to directory of files:
bazel-bin/converter/export_xyz --input_path=input.wtiles --output_path="tiles/{z}/{x}/{y}.png"

# Import directory of files into webtiles file:
bazel-bin/converter/import_xyz --input_path="tiles/{z}/{x}/{y}.png" --output_path=output.wtiles
```

### C++ Reader/Writer

```cpp
#include "webtiles/reader.h"
#include "webtiles/writer.h"

webtiles::WriterParams params = {
    .filePath = "output.wtiles",
    .metadata = R"({"foo": "bar"})",
    .indexFormat = webtiles::IndexFormat::Sparse,
};
auto writer = webtiles::createWriter(params);
writer->writeTile({.x = 0, .y = 0, .z = 0}, "tile data");
writer->finalize();

auto reader = webtiles::createFileReader("output.wtiles");
auto tileData = reader->readTileData({.x = 0, .y = 0, .z = 0});

for (const auto& [tileId, tileData] : reader->allTiles()) {
    // process tileId (x, y, z) and tileData
}
```

### Lua Module and Nginx Server

`handle_tiles.lua`:
```lua
local wt = require("webtiles")
local x, y, z = ...
local function fileAccess(offset, size)
    -- read file via io.open or other methods
end
local tileData = wt.readTileData(x, y, z, fileAccess)
ngx.print(tileData)
```

`nginx.conf`:
```nginx
location ~ /tiles/\d+/\d+/\d+ {
    content_by_lua_file /usr/local/openresty/nginx/lua/handle_tiles.lua;
}
```

Build docker image with nginx example:
```bash
bazel build //server_nginx:docker_pkg
docker build -t webtiles-nginx-dev - < bazel-bin/server_nginx/docker_pkg.tar.gz
```

## Repository Structure

```
webtiles/      # C++ library for reading and writing .wtiles files
webtiles/fbs/  # FlatBuffers schema defining the format
converter/     # Command-line tools to convert datasets from/to other formats
lua/           # Lua implementation, compatible with Lua 5.1+ and LuaJIT
server_nginx/  # Example Nginx/OpenResty configuration and Lua scripts to serve tiles from .wtiles file
```

## Perfomance comparison

Hardware configuration: AMD EPYC 9654, 96 CPU, 25 GbE network. Datasets were stored in tmpfs.  
Load profile is based on requests from OSM [tile_logs](https://planet.openstreetmap.org/tile_logs/).

| Tile Storage Format  | small_z14                  | medium_z12               | large_z15                |
|----------------------|----------------------------|--------------------------|--------------------------|
| IndexFormat::Basic   | 100k+ RPS, 24 Gbps, 7 CPU  | 59k RPS, 25 Gbps, 9 CPU  | 80k RPS, 25 Gbps, 7 CPU  |
| IndexFormat::Sparse  | 100k+ RPS, 24 Gbps, 19 CPU | 59k RPS, 25 Gbps, 14 CPU | 80k RPS, 25 Gbps, 42 CPU |
| static files z/x/y   | 100k+ RPS, 24 Gbps, 5 CPU  | 59k RPS, 25 Gbps, 5 CPU  | fail¹                    |
| mbtileserver v0.11.0 | 51k RPS, 12 Gbps, 46 CPU   | 32k RPS, 14 Gbps, 36 CPU | 40k RPS, 13 Gbps, 52 CPU |
| go-pmtiles v1.29.1   | 38k RPS, 9 Gbps, 14 CPU    | 29k RPS, 12 Gbps, 17 CPU | 36k RPS, 11 Gbps, 13 CPU |

¹ _Ran out of inodes due to too many files._  

`large_z15` — tiles from `20251229.pmtiles`, `~120 GiB`.  
`medium_z12` — tiles from `20251229.pmtiles`, zooms 0-12 only, `~16 GiB`.  
`small_z14` — tiles from `2024-12-27-netherlands.mbtiles`, 52071 tiles, `~650 MiB`.  

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

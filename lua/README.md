# Lua

Dependencies:
- `flatbuffers` (included)
- `bit` for lua5.1 (https://github.com/LuaDist/bitlib)

## Tests

```
$ bazel build testdata
$ cd lua
$ lua5.3 webtiles_test.lua
$ lua5.1 webtiles_test.lua
$ luajit webtiles_test.lua
```

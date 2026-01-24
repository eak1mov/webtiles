#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace webtiles {

class Error : public std::runtime_error {
    using runtime_error::runtime_error;
};
class AssertionError : public Error {
    using Error::Error;
};
class InvalidDatasetError : public Error {
    using Error::Error;
};
class InvalidRequestError : public Error {
    using Error::Error;
};
class InvalidFileFormatError : public Error {
    using Error::Error;
};
class InvalidVersionError : public Error {
    using Error::Error;
};

struct TileId {
    uint32_t x;
    uint32_t y;
    uint32_t z;

    auto operator<=>(const TileId&) const = default;
};

struct __attribute__((packed)) PackedLocation {
    uint64_t offset : 40; // max 2^40 = 1024 GiB
    uint64_t size : 24; // max 2^24 = 16 MiB

    bool operator==(const PackedLocation&) const = default;
};
static_assert(sizeof(PackedLocation) == sizeof(uint64_t));

using Zoom = uint32_t;
using ZoomLevels = std::vector<Zoom>;

// owning / non-owning reference to memory,
// can be useful for memory stored in cache (with custom deleter)
class FileData {
public:
    FileData(std::string_view data)
        : data_{data.data(), [](auto) {}}
        , size_{data.size()}
    { }
    FileData(std::shared_ptr<const std::string> data)
        : data_{data, data->data()}
        , size_{data->size()}
    { }
    FileData(std::shared_ptr<const char> data, size_t size)
        : data_{std::move(data)}
        , size_{size}
    { }

    const char* data() const { return data_.get(); }
    size_t size() const { return size_; }

    operator std::string_view() const { return {data(), size()}; }
    bool operator==(std::string_view other) const { return other == std::string_view{*this}; }

private:
    std::shared_ptr<const char> data_;
    size_t size_;
};

// must ensure that there are no partial reads
using FileAccess = std::function<FileData(PackedLocation)>;

} // namespace webtiles

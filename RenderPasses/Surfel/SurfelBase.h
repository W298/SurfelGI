#pragma once

using namespace Falcor;

namespace
{
const uint2 kTileSize = uint2(16, 16);
const uint32_t kSurfelLimit = 1000;
const float kSurfelRadius = 0.008f;
} // namespace

struct Surfel
{
    float3 position;
    float3 normal;
    float3 color;
    bool valid;
};

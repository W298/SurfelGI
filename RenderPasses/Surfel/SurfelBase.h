#pragma once

using namespace Falcor;

namespace
{
const uint2 kTileSize = uint2(16, 16);
const uint32_t kSurfelLimit = 100;
const float kSurfelRadius = 0.01f;
} // namespace

struct Surfel
{
    float3 position;
    float3 normal;
    bool valid;
};

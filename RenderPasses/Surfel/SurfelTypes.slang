#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

static const uint2 kTileSize = uint2(16, 16);
static const uint32_t kSurfelLimit = 5000;
static const float kSurfelRadius = 0.008f;

struct Surfel
{
    float3 position;
    float3 normal;
    float3 color;
    bool valid;
};

END_NAMESPACE_FALCOR

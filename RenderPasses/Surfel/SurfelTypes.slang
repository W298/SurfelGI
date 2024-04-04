#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

static const uint2 kTileSize = uint2(16, 16);
static const uint32_t kSurfelLimit = 51200;
static const uint32_t kCellSurfelLimit = 4;
static const float kSurfelRadius = 0.008f;
static const float kCellUnit = 0.01f;
static const uint3 kCellDimension = uint3(500, 500, 500);
static const uint32_t kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

enum class SurfelStatusOffset : uint32_t
{
    SurfelCount = 0u,
    CellCount = sizeof(uint32_t) * 1u
};

struct Surfel
{
    float3 position;
    float3 normal;
    float3 color;
};

struct CellInfo
{
    uint count;
    uint offset;
};

END_NAMESPACE_FALCOR

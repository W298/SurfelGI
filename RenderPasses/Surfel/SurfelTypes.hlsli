#ifndef SURFEL_TYPES_H
#define SURFEL_TYPES_H

static const uint2 kTileSize = uint2(16, 16);
static const uint kTotalSurfelLimit = 51200;
static const uint kPerCellSurfelLimit = 16;
static const float kCoverageThreshold = 1e-12f;
static const float kSurfelRadius = 0.008f;
static const float kCellUnit = 0.01f;
static const uint3 kCellDimension = uint3(300, 300, 300);
static const uint kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kSurfelStatus_TotalSurfelCount = 0;
static const uint kSurfelStatus_CellCount = sizeof(uint) * 1u;

struct Surfel
{
    float3 position;
    float3 normal;
    float3 color;
    uint4 packedHitInfo;
};

struct CellInfo
{
    uint surfelCount;
    uint cellToSurfelBufferOffset;
};

#endif

#ifndef SURFEL_TYPES_H
#define SURFEL_TYPES_H

#define SURFEL_COUNTER_VALID_SURFEL         0
#define SURFEL_COUNTER_FREE_SURFEL          4
#define SURFEL_COUNTER_CELL                 8

static const uint2 kTileSize = uint2(16, 16);
static const uint kTotalSurfelLimit = 409600;
static const uint kPerCellSurfelLimit = 24;
static const uint kChancePower = 6;
static const float kChaneMultiply = 1.f;
static const float kCoverageThreshold = 1e-12f;
static const float kSurfelRadius = 0.008f;
static const float kCellUnit = 0.02f;
static const uint3 kCellDimension = uint3(400, 400, 400);
static const uint kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kInitialStatus[] = { 0, kTotalSurfelLimit, 0 };

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

#ifndef SURFEL_TYPES_H
#define SURFEL_TYPES_H

#define USE_RAYTRACE_AS_PRIMITIVE_PICK      0
#define VARIABLE_SURFEL_RADIUS              1

#define SURFEL_COUNTER_VALID_SURFEL         0
#define SURFEL_COUNTER_DIRTY_SURFEL         4
#define SURFEL_COUNTER_FREE_SURFEL          8
#define SURFEL_COUNTER_CELL                 12

static const uint2 kTileSize = uint2(16, 16);
static const uint kTotalSurfelLimit = 409600;
static const uint kPerCellSurfelLimit = 64;
static const uint kChancePower = 4;
static const float kChanceMultiply = 1.0f;
static const float kPlacementThreshold = 1e-12f;
static const float kRemovalThreshold = 1.0f;
static const float kSurfelStaticRadius = 0.008f;
static const float kSurfelTargetArea = 1200.0f;
static const float kCellUnit = 0.02f;
static const uint3 kCellDimension = uint3(400, 400, 400);
static const uint kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kInitialStatus[] = { 0, 0, kTotalSurfelLimit, 0 };

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    float3 color;
    uint4 packedHitInfo;
};

struct CellInfo
{
    uint surfelCount;
    uint cellToSurfelBufferOffset;
};

#endif

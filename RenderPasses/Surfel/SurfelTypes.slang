#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

enum class SurfelCounterOffset : int
{
    ValidSurfel = 0,
    DirtySurfel = 4,
    FreeSurfel = 8,
    Cell = 12,
    RequestedRay = 16
};

static const uint2 kTileSize = uint2(16, 16);
static const uint kTotalSurfelLimit = 409600;
static const uint kRayBudget = 4096;
static const uint kChancePower = 1;
static const float kChanceMultiply = 0.3f;
static const bool useRaytraceAsPrimitivePick = false;
static const bool kVariableSurfelRadius = true;
static const float kStaticSurfelRadius = 0.008f;
static const float kPlacementThreshold = 0;
static const float kRemovalThreshold = 1.5f;
static const uint3 kCellDimension = uint3(400, 400, 400);
static const uint kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kInitialStatus[] = { 0, 0, kTotalSurfelLimit, 0, 0 };

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    float3 color;
    uint4 packedHitInfo;
    uint rayOffset;
    uint rayCount;
};

struct CellInfo
{
    uint surfelCount;
    uint cellToSurfelBufferOffset;
};

struct SurfelConfig
{
    float surfelTargetArea = 2000.0f;
    float cellUnit = 0.02f;
    uint perCellSurfelLimit = 64;
    float surfelVisualRadius = 0.7f;
};

struct SurfelRay
{
    float3 direction;
    float depth;
    float3 radiance;
    uint surfelIndex;
};

END_NAMESPACE_FALCOR

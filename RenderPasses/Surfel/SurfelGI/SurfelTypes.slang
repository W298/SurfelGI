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
static const uint kRayBudget = 409600 * 10;
static const float kRayTMax = 3.402823466e+38F;
static const uint kChancePower = 1;
static const float kChanceMultiply = 0.3f;
static const bool kVariableSurfelRadius = true;
static const float kStaticSurfelRadius = 0.008f;
static const float kPlacementThreshold = 2.f;
static const float kRemovalThreshold = 4.f;
static const uint3 kCellDimension = uint3(400, 400, 400);
static const uint kCellCount = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kInitialStatus[] = { 0, 0, kTotalSurfelLimit, 0, 0 };

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    uint4 packedHitInfo;
    float3 radiance;
    uint accumulated;
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
    float surfelTargetArea = 12000.f;
    float cellUnit = 0.035f;
    uint perCellSurfelLimit = 512;
    float surfelVisualRadius = 1.f;
};

struct SurfelRayResult
{
    float3 direction;
    float depth;
    float3 radiance;
    uint surfelIndex;
};

END_NAMESPACE_FALCOR

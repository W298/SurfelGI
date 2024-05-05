#pragma once
#include "Utils/HostDeviceShared.slangh"
#include "MultiscaleMeanEstimator.slang"

BEGIN_NAMESPACE_FALCOR

enum class SurfelCounterOffset : int
{
    ValidSurfel     = 0,
    DirtySurfel     = 4,
    FreeSurfel      = 8,
    Cell            = 12,
    RequestedRay    = 16
};

static const uint2 kTileSize            = uint2(16, 16);
static const uint kTotalSurfelLimit     = 4096000;
static const uint kRayBudget            = 40960000;
static const uint3 kCellDimension       = uint3(400, 400, 400);
static const uint kCellCount            = kCellDimension.x * kCellDimension.y * kCellDimension.z;

static const uint kInitialStatus[] = { 0, 0, kTotalSurfelLimit, 0, 0 };

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    uint4 packedHitInfo;
    float3 radiance;
    MSMEData msmeData;
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
    float surfelTargetArea  = 30000.f;
    float cellUnit          = 0.1f;
    uint perCellSurfelLimit = 1024u;
};

struct SurfelRayResult
{
    float3 direction;
    float depth;
    float3 radiance;
    uint surfelIndex;
};

END_NAMESPACE_FALCOR

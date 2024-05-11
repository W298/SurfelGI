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

static const uint2 kTileSize                = uint2(16, 16);
static const uint kTotalSurfelLimit         = 150000;
static const uint kRayBudget                = 40960000;
static const uint3 kCellDimension           = uint3(200, 200, 200);
static const uint kCellCount                = kCellDimension.x * kCellDimension.y * kCellDimension.z;
static const uint2 kIrradianceMapRes        = uint2(3840, 2160);
static const uint2 kIrradianceMapUnit       = uint2(7, 7);
static const uint2 kIrradianceMapHalfUnit   = kIrradianceMapUnit / 2u;

static const uint kInitialStatus[] = { 0, 0, kTotalSurfelLimit, 0, 0 };

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    uint4 packedHitInfo;
    float3 radiance;
    float sumLuminance;
    bool hasHole;
    MSMEData msmeData;
    uint frame;
    uint rayOffset;
    uint rayCount;

#ifdef HOST_CODE
#else
    __init(float3 position, float3 normal, float radius, uint4 packedHitInfo)
    {
        this.position = position;
        this.normal = normal;
        this.radius = radius;
        this.packedHitInfo = packedHitInfo;
        this.radiance = float3(0.f);
        this.sumLuminance = 0.f;
        this.hasHole = false;
        this.msmeData = MSMEData();
        this.frame = 0;
        this.rayOffset = 0;
        this.rayCount = 0;
    }
#endif
};

struct CellInfo
{
    uint surfelCount;
    uint cellToSurfelBufferOffset;
};

struct SurfelConfig
{
    float surfelTargetArea  = 40000.f;
    float cellUnit          = 0.1f;
    uint perCellSurfelLimit = 1024u;
};

struct SurfelRayResult
{
    float3 dirLocal;
    float3 dirWorld;
    float pdf;
    float depth;
    float3 radiance;
    uint surfelIndex;
};

END_NAMESPACE_FALCOR

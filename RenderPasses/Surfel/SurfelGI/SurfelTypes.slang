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
    RequestedRay    = 16,
    MissBounce      = 20
};

static const uint2 kTileSize                = uint2(16, 16);
static const uint kTotalSurfelLimit         = 150000;
static const uint kRayBudget                = 150000 * 64;
static const uint kRefCountThreshold        = 32u;
static const uint kMaxLife                  = 240u;
static const uint kSleepingMaxLife          = kMaxLife / 4;
static const uint kInitialStatus[]          = { 0, 0, kTotalSurfelLimit, 0, 0, 0 };

static const uint2 kIrradianceMapRes        = uint2(3840, 2160);
static const uint2 kIrradianceMapUnit       = uint2(7, 7);
static const uint2 kIrradianceMapHalfUnit   = kIrradianceMapUnit / 2u;

static const uint2 kSurfelDepthTextureRes = uint2(3840, 2160);
static const uint2 kSurfelDepthTextureUnit = uint2(7, 7);
static const uint kSrufelDepthTexturePadding = 1u;
static const uint2 kSurfelDepthTextureHalfUnit = kSurfelDepthTextureUnit / 2u;

struct Surfel
{
    float3 position;
    float3 normal;
    float radius;
    float3 radiance;
    float sumLuminance;
    bool hasHole;
    MSMEData msmeData;
    uint rayOffset;
    uint rayCount;

#ifdef HOST_CODE
#else
    __init(float3 position, float3 normal, float radius)
    {
        this.position = position;
        this.normal = normal;
        this.radius = radius;
        this.radiance = float3(0.f);
        this.sumLuminance = 0.f;
        this.hasHole = false;
        this.msmeData = MSMEData();
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

struct SurfelRayResult
{
    float3 dirLocal;
    float3 dirWorld;
    float pdf;
    float firstRayLength;
    float3 radiance;
    uint surfelIndex;
};

// [status]
// 0x0001 : isSleeping
// 0x0002 : lastSeen
struct SurfelRecycleInfo
{
    uint16_t life;
    uint16_t frame;
    uint16_t status;
};

END_NAMESPACE_FALCOR

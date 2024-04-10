#include "../Random.hlsli"
#include "../SurfelTypes.hlsli"
#include "../SurfelUtils.hlsli"

import Scene.RaytracingInline;

cbuffer CB
{
    uint2 gResolution;
    float2 gInvResolution;
    float gFOVy;
    float4x4 gInvViewProj;
    uint gFrameIndex;
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint> gSurfelFreeIndexBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWByteAddressBuffer gSurfelCounter;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

Texture2D<float> gDepth;
Texture2D<float4> gNormal;
Texture2D<uint> gCoverage;
Texture2D<uint4> gPackedHitInfo;

RWTexture2D<float4> gSurfel;

uint4 getPixelInfo(uint2 pixelPos)
{
#if USE_RAYTRACE_AS_PRIMITIVE_PICK
    const Ray ray = gScene.camera.computeRayPinhole(pixelPos, gResolution);
    SceneRayQuery<0> sceneRayQuery;

    HitInfo hit;
    float hitT;
    sceneRayQuery.traceRay(ray, hit, hitT, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xff);
    return hit.getTriangleHit().pack();
#else
    return gPackedHitInfo[pixelPos];
#endif
}

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID)
{
    uint2 tilePos = dispatchThreadId.xy / kTileSize;
    uint2 pixelPos = dispatchThreadId.xy;

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    uint coverageData = gCoverage[tilePos];
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

    float3 worldPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    int3 cellPos = getCellPos(worldPos, gCameraPos);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    if (cellInfo.surfelCount < kPerCellSurfelLimit)
    {
        if (groupThreadID.x == x && groupThreadID.y == y && coverage <= kCoverageThreshold)
        {
            const float chance = pow(depth, kChancePower);
            RandomState randomState = initRandomState(pixelPos, gFrameIndex);

            if (getNextFloat(randomState) < chance * kChaneMultiply)
            {
                int freeSurfelCount;
                gSurfelCounter.InterlockedAdd(SURFEL_COUNTER_FREE_SURFEL, -1, freeSurfelCount);

                if (0 < freeSurfelCount && freeSurfelCount <= kTotalSurfelLimit)
                {
                    uint validSurfelCount;
                    gSurfelCounter.InterlockedAdd(SURFEL_COUNTER_VALID_SURFEL, 1, validSurfelCount);

                    if (validSurfelCount < kTotalSurfelLimit)
                    {
                        uint newIndex = gSurfelFreeIndexBuffer[freeSurfelCount - 1];

                        float3 normal = gNormal[pixelPos].xyz;
                        float3 randomColor = getNextFloat3(randomState);
                        float radius = calcSurfelRadius(
                            distance(gScene.camera.getPosition(), worldPos),
                            gFOVy,
                            gResolution
                        );

                        Surfel newSurfel = {
                            worldPos,
                            normal,
                            radius,
                            randomColor,
                            getPixelInfo(pixelPos)
                        };

                        gSurfelValidIndexBuffer[validSurfelCount] = newIndex;
                        gSurfelBuffer[newIndex] = newSurfel;
                    }
                }
            }
        }
    }

    // Visualize
    float3 topColor = float3(0, 0, 0);
    uint top = 0;
    bool noSurfel = true;

    for (uint i = 0; i < cellInfo.surfelCount; ++i)
    {
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        float3 bias = worldPos - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < surfel.radius * surfel.radius)
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(gNormal[pixelPos].xyz, normal);
            if (dotN > 0)
            {
                if (surfelIndex > top)
                {
                    topColor = surfel.color;
                    top = surfelIndex;
                    noSurfel = false;
                }
            }
        }
    }

    gSurfel[pixelPos] = float4(topColor, noSurfel ? 0 : 1);
}

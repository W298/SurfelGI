import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtils;

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
ByteAddressBuffer gSurfelConfig;

RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

Texture2D<float> gDepth;
Texture2D<float4> gNormal;
RWTexture2D<uint2> gCoverage;
Texture2D<uint4> gPackedHitInfo;
Texture2D<float4> gRaster;

RWTexture2D<float4> gSurfel;

uint4 getPixelInfo(uint2 pixelPos)
{
    if (useRaytraceAsPrimitivePick)
    {
        const Ray ray = gScene.camera.computeRayPinhole(pixelPos, gResolution);
        SceneRayQuery<0> sceneRayQuery;

        HitInfo hit;
        float hitT;
        sceneRayQuery.traceRay(ray, hit, hitT, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xff);
        return hit.getTriangleHit().pack();
    }

    return gPackedHitInfo[pixelPos];
}

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID, uint3 groupdId: SV_GroupID)
{
    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 tilePos = groupdId.xy;
    uint2 pixelPos = dispatchThreadId.xy;

    RNG randomState;
    randomState.init(pixelPos, gFrameIndex);

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    float depth = gDepth[pixelPos];
    if (depth == 1)
    {
        gSurfel[pixelPos] = gRaster[pixelPos];
        return;
    }

    uint coverageData = gCoverage[tilePos].x;
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

    float3 worldPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    int3 cellPos = getCellPos(worldPos, gCameraPos, config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    if (cellInfo.surfelCount < config.perCellSurfelLimit)
    {
        if (groupThreadID.x == x && groupThreadID.y == y)
        {
            if (coverage <= kPlacementThreshold)
            {
                const float chance = pow(depth, kChancePower);
                if (randomState.next_float() < chance * kChanceMultiply)
                {
                    int freeSurfelCount;
                    gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::FreeSurfel, -1, freeSurfelCount);

                    if (0 < freeSurfelCount && freeSurfelCount <= kTotalSurfelLimit)
                    {
                        uint validSurfelCount;
                        gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::ValidSurfel, 1, validSurfelCount);

                        if (validSurfelCount < kTotalSurfelLimit)
                        {
                            uint newIndex = gSurfelFreeIndexBuffer[freeSurfelCount - 1];
                            uint4 packedHitInfo = getPixelInfo(pixelPos);

                            float3 normal = gNormal[pixelPos].xyz;
                            // float3 surfelColor = randomizeColor(gRaster[pixelPos].xyz, randomState);
                            float3 surfelColor = randomizeColor(pseudocolor(TriangleHit(packedHitInfo).instanceID.index), randomState);
                            // float3 surfelColor = (pseudocolor(cellPos.x) + pseudocolor(cellPos.y) + pseudocolor(cellPos.z)) / 3.0f;

                            float radius = calcSurfelRadius(
                                distance(gScene.camera.getPosition(), worldPos),
                                gFOVy,
                                gResolution,
                                config.surfelTargetArea,
                                config.cellUnit
                            );

                            Surfel newSurfel = {
                                worldPos,
                                normal,
                                radius,
                                surfelColor,
                                packedHitInfo
                            };

                            gSurfelValidIndexBuffer[validSurfelCount] = newIndex;
                            gSurfelBuffer[newIndex] = newSurfel;
                        }
                    }
                }
            }
        }
    }

    if (cellInfo.surfelCount > 0)
    {
        if (groupThreadID.x == x && groupThreadID.y == y)
        {
            if (coverage > kRemovalThreshold)
            {
                const float chance = pow(depth, kChancePower);
                if (randomState.next_float() < chance * kChanceMultiply)
                {
                    uint contributionData = gCoverage[tilePos].y;
                    float maxContribution = f16tof32((contributionData & 0xFFFF0000) >> 16);
                    uint maxContributionSurfelIndex = (contributionData & 0x0000FFFF) >> 0;

                    uint toDestroySurfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + maxContributionSurfelIndex];
                    Surfel toDestroySurfel = gSurfelBuffer[toDestroySurfelIndex];

                    toDestroySurfel.radius = 0;
                    gSurfelBuffer[toDestroySurfelIndex] = toDestroySurfel;
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

        if (dist2 < pow(surfel.radius * config.surfelVisualRadius, 2))
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

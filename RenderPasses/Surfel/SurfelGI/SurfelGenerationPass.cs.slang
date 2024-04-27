import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.HashUtils;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

import Scene.Scene;

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
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWByteAddressBuffer gSurfelCounter;
ByteAddressBuffer gSurfelConfig;

Texture2D<uint4> gPackedHitInfo;

groupshared uint groupShareMinCoverage;
groupshared uint groupShareMaxContribution;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint groupIndex: SV_GroupIndex, uint3 groupThreadID: SV_GroupThreadID, uint3 groupdId: SV_GroupID)
{
    if (groupIndex == 0)
    {
        groupShareMinCoverage = ~0;
        groupShareMaxContribution = 0;
    }

    GroupMemoryBarrierWithGroupSync();

    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 tilePos = groupdId.xy;
    uint2 pixelPos = dispatchThreadId.xy;

    RNG randomState;
    randomState.init(pixelPos, gFrameIndex);

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
        return;

    TriangleHit triangleHit = hitInfo.getTriangleHit();
    VertexData v = gScene.getVertexData(triangleHit);
    float depth = smoothstep(gScene.camera.data.farZ, gScene.camera.data.nearZ, distance(gScene.camera.getPosition(), v.posW));

    int3 cellPos = getCellPos(v.posW, gCameraPos, config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // Evaluate Coverage.
    {
        float coverage = 0.f;

        float maxContribution = 0.f;
        uint maxContributionSurfelIndex = randomState.next_uint(cellInfo.surfelCount);

        for (uint i = 0; i < cellInfo.surfelCount; ++i)
        {
            uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
            Surfel surfel = gSurfelBuffer[surfelIndex];

            float3 bias = v.posW - surfel.position;
            float dist2 = dot(bias, bias);

            if (dist2 < surfel.radius * surfel.radius)
            {
                float3 normal = normalize(surfel.normal);

                float dotN = dot(v.normalW, normal);
                if (dotN > 0)
                {
                    float dist = sqrt(dist2);
                    float contribution = 1.f;

                    contribution *= saturate(dotN);
                    contribution *= saturate(1 - dist / surfel.radius);
                    contribution = smoothstep(0, 1, contribution);
                    coverage += contribution;

                    if (maxContribution < contribution)
                    {
                        maxContribution = contribution;
                        maxContributionSurfelIndex = i;
                    }
                }
            }
        }

        uint coverageData = 0;
        coverageData |= ((f32tof16(coverage) & 0x0000FFFF) << 16);
        coverageData |= ((randomState.next_uint(255) & 0x000000FF) << 8);
        coverageData |= ((groupThreadID.x & 0x0000000F) << 4);
        coverageData |= ((groupThreadID.y & 0x0000000F) << 0);

        InterlockedMin(groupShareMinCoverage, coverageData);

        uint contributionData = 0;
        contributionData |= ((f32tof16(maxContribution) & 0x0000FFFF) << 16);
        contributionData |= ((maxContributionSurfelIndex & 0x0000FFFF) << 0);

        InterlockedMax(groupShareMaxContribution, contributionData);

        GroupMemoryBarrierWithGroupSync();
    }

    uint coverageData = groupShareMinCoverage;
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

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

                            float3 normal = v.normalW;
                            float3 surfelColor = randomizeColor(pseudocolor(triangleHit.instanceID.index), randomState);

                            float radius = calcSurfelRadius(
                                distance(gScene.camera.getPosition(), v.posW),
                                gFOVy,
                                gResolution,
                                config.surfelTargetArea,
                                config.cellUnit
                            );

                            Surfel newSurfel = {
                                v.posW,
                                normal,
                                radius,
                                surfelColor,
                                hitInfo.data
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
                    uint contributionData = groupShareMaxContribution;
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
}

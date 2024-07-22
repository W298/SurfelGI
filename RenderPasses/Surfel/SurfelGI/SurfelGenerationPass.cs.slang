import Scene.Scene;
import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.HashUtils;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;
import RenderPasses.Surfel.SurfelGI.StaticParams;

cbuffer CB
{
    uint2 gResolution;
    float gFOVy;
    uint gFrameIndex;
    float gChanceMultiply;
    uint gChancePower;
    float gPlacementThreshold;
    float gRemovalThreshold;
    uint gBlendingDelay;
    uint gOverlayMode;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint4> gSurfelGeometryBuffer;
RWStructuredBuffer<uint> gSurfelFreeIndexBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRecycleInfo> gSurfelRecycleInfoBuffer;

RWByteAddressBuffer gSurfelRefCounter;
RWByteAddressBuffer gSurfelCounter;

Texture2D<uint4> gPackedHitInfo;
RWTexture2D<float4> gOutput;
RWTexture2D<float4> gDebug;

groupshared uint groupShareMinCoverage;
groupshared uint groupShareMaxContribution;

[numthreads(16, 16, 1)]
void csMain(
    uint3 dispatchThreadId: SV_DispatchThreadID,
    uint groupIndex: SV_GroupIndex,
    uint3 groupThreadID: SV_GroupThreadID,
    uint3 groupdId: SV_GroupID
)
{
    // Initialize group shared values.
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

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
        return;

    TriangleHit triangleHit = hitInfo.getTriangleHit();
    VertexData v = gScene.getVertexData(triangleHit);
    float4 curPosH = mul(gScene.camera.data.viewProjMatNoJitter, float4(v.posW, 1.f));
    float depth = curPosH.z / curPosH.w;

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), kCellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // Evaluate min coverage value and pixel position.
    // Also evaluate max contribution and surfel index (for handling over-coverage).
    // Also evalute weighted color output (indrect lighting).
    float4 indirectLighting = float4(0.f);
    {
        float coverage = 0.f;
        float varianceEx = 0.f;
        float rayCountEx = 0.f;
        uint refCount = 0;
        uint life = 0;

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
                    const SurfelRecycleInfo surfelRecycleInfo = gSurfelRecycleInfoBuffer[surfelIndex];
                    bool isSleeping = surfelRecycleInfo.status & 0x0001;
                    bool lastSeen = surfelRecycleInfo.status & 0x0002;

                    if (!isSleeping)
                    {
                        float dist = sqrt(dist2);
                        float contribution = 1.f;

                        contribution *= saturate(dotN);
                        contribution *= saturate(1 - dist / surfel.radius);
                        contribution = smoothstep(0, 1, contribution);

                        coverage += contribution;

                        // Delay blending if not sufficient sample is accumulated.
                        // Because samples are updated per frame, so do not use sample count directly.
                        indirectLighting += float4(surfel.radiance, 1.f) * contribution * smoothstep(0, gBlendingDelay, surfelRecycleInfo.frame);

                        varianceEx += length(surfel.msmeData.variance) * contribution;
                        rayCountEx += surfel.rayCount * contribution;

                        refCount = max(refCount, gSurfelRefCounter.Load(surfelIndex));
                        life = max(life, surfelRecycleInfo.life);

                        if (maxContribution < contribution)
                        {
                            maxContribution = contribution;
                            maxContributionSurfelIndex = i;
                        }
                    }

                    if (!lastSeen)
                        gSurfelRecycleInfoBuffer[surfelIndex].status |= 0x0002;
                }
            }
        }

        if (indirectLighting.w > 0)
        {
            indirectLighting.xyz /= indirectLighting.w;
            indirectLighting.w = saturate(indirectLighting.w);

            varianceEx /= indirectLighting.w;
            rayCountEx /= indirectLighting.w;

            // Write texture by overlay mode.
            if (gOverlayMode == 0)
            {
                gOutput[pixelPos] = indirectLighting;
            }
            else if (gOverlayMode == 1)
            {
                gOutput[pixelPos] = float4(stepColor(varianceEx, 0.1f, 0.05f), 1);
            }
            else if (gOverlayMode == 2)
            {
                gOutput[pixelPos] = float4(stepColor(rayCountEx, 48.f, 32.f), 1);
            }
            else if (gOverlayMode == 3)
            {
                gOutput[pixelPos] = float4(lerpColor(refCount / 256.f), 1);
            }
            else if (gOverlayMode == 4)
            {
                gOutput[pixelPos] = float4(step(life, 0u), step(1u, life), 0, 1);
            }
            else if (gOverlayMode == 5)
            {
                gOutput[pixelPos] = float4(lerpColor(smoothstep(gPlacementThreshold, gRemovalThreshold, coverage)), 1);
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

    if (cellInfo.surfelCount < kPerCellSurfelLimit)
    {
        if (groupThreadID.x == x && groupThreadID.y == y)
        {
            // If seat for surfel in current cell avaliable and coverage is under threshold,
            // genearte new surfel probabilistically.
            if (coverage <= gPlacementThreshold)
            {
                const float chance = pow(depth, gChancePower);
                if (randomState.next_float() < chance * gChanceMultiply)
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

                            float varRadius = calcSurfelRadius(
                                distance(gScene.camera.getPosition(), v.posW),
                                gFOVy,
                                gResolution,
                                kSurfelTargetArea,
                                kCellUnit
                            );

                            Surfel newSurfel = Surfel(v.posW, v.normalW, varRadius);

                            newSurfel.radiance = indirectLighting.xyz;
                            newSurfel.msmeData.mean = indirectLighting.xyz;
                            newSurfel.msmeData.shortMean = indirectLighting.xyz;

                            gSurfelValidIndexBuffer[validSurfelCount] = newIndex;
                            gSurfelBuffer[newIndex] = newSurfel;
                            gSurfelRecycleInfoBuffer[newIndex] = { kMaxLife, 0u, 0u };
                            gSurfelGeometryBuffer[newIndex] = hitInfo.data;
                            gSurfelRefCounter.Store(newIndex, 0);
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
            // If coverage is upper removal threshold,
            // remove surfel that most contribute to coverage probabilistically.
            if (coverage > gRemovalThreshold)
            {
                const float chance = pow(depth, gChancePower);
                if (randomState.next_float() < chance * gChanceMultiply)
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

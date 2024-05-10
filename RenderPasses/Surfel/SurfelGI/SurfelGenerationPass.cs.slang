import Scene.Scene;
import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.HashUtils;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

cbuffer CB
{
    uint2 gResolution;
    float gFOVy;
    uint gFrameIndex;
    float gChanceMultiply;
    uint gChancePower;
    float gPlacementThreshold;
    float gRemovalThreshold;
    bool gShowVariance;
    uint gBlendingDelay;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint> gSurfelFreeIndexBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWByteAddressBuffer gSurfelCounter;
ByteAddressBuffer gSurfelConfig;

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

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
        return;

    TriangleHit triangleHit = hitInfo.getTriangleHit();
    VertexData v = gScene.getVertexData(triangleHit);
    float depth = smoothstep(gScene.camera.data.farZ, gScene.camera.data.nearZ, distance(gScene.camera.getPosition(), v.posW));

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // Evaluate min coverage value and pixel position.
    // Also evaluate max contribution and surfel index (for handling over-coverage).
    // Also evalute weighted color output (indrect lighting).
    {
        float coverage = 0.f;
        float4 outputColor = float4(0, 0, 0, 0);
        float variance = 0.f;
        uint maxRayCount = 0;

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

                    // Delay blending if not sufficient sample is accumulated.
                    outputColor += float4(surfel.radiance, 1.f) * contribution * smoothstep(0, gBlendingDelay, surfel.sampleCount);
                    variance += length(surfel.msmeData.variance) * contribution;

                    maxRayCount = max(maxRayCount, surfel.rayCount);

                    if (maxContribution < contribution)
                    {
                        maxContribution = contribution;
                        maxContributionSurfelIndex = i;
                    }
                }
            }
        }

        if (outputColor.w > 0)
        {
            outputColor.xyz /= outputColor.w;
            outputColor.w = saturate(outputColor.w);

            variance /= outputColor.w;
        }

        if (maxRayCount > 16u)
            gDebug[pixelPos] = float4(1.f, 0, 0, 1);
        else if (maxRayCount > 8u)
            gDebug[pixelPos] = float4(1.f, 1.f, 0, 1);
        else
            gDebug[pixelPos] = float4(0, 1.f, 0, 1);

        if (gShowVariance)
        {
            if (variance > 0.1f)
                gOutput[pixelPos] = float4(1, 0, 0, 1);
            else if (variance > 0.05f)
                gOutput[pixelPos] = float4(0, 1, 0, 1);
            else
                gOutput[pixelPos] = float4(0, 0, 1, 1);
        }
        else
            gOutput[pixelPos] = outputColor;

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
                                config.surfelTargetArea,
                                config.cellUnit
                            );

                            Surfel newSurfel = Surfel(v.posW, v.normalW, varRadius, hitInfo.data);

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

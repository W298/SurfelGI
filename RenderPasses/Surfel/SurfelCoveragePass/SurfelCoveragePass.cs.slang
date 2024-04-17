import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtils;

cbuffer CB
{
    uint2 gResolution;
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint gFrameIndex;
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

ByteAddressBuffer gSurfelConfig;

Texture2D<float> gDepth;
Texture2D<float4> gNormal;

RWTexture2D<uint2> gCoverage;
RWTexture2D<float4> gDebug;

groupshared uint groupShareMinCoverage;
groupshared uint groupShareMaxContribution;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 groupThreadID : SV_GroupThreadID, uint3 groupdId: SV_GroupID)
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

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    float3 worldPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    int3 cellPos = getCellPos(worldPos, gCameraPos, config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    float coverage = 0.f;

    float maxContribution = 0.f;
    uint maxContributionSurfelIndex = randomState.next_uint(cellInfo.surfelCount);

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

    float groupMinCoverage = f16tof32((groupShareMinCoverage & 0xFFFF0000) >> 16);
    gDebug[pixelPos] = float4(step(kRemovalThreshold, groupMinCoverage), step(groupMinCoverage, kPlacementThreshold), 0, 1);

    gCoverage[tilePos] = uint2(groupShareMinCoverage, groupShareMaxContribution);
}

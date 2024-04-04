import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

cbuffer CB
{
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint32_t gFrameIndex;
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint32_t> gCellIndexBuffer;

Texture2D<float> gDepth;
Texture2D<float4> gNormal;

RWTexture2D<uint> gCoverage;

groupshared uint groupShareMinCoverage;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 groupThreadID : SV_GroupThreadID)
{
    if (groupIndex == 0)
    {
        groupShareMinCoverage = ~0;
    }
    GroupMemoryBarrierWithGroupSync();

    uint2 tilePos = dispatchThreadId.xy / kTileSize;
    uint2 pixelPos = dispatchThreadId.xy;

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    float3 worldPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    int3 cellPos = getCellPos(worldPos, gCameraPos);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    float coverage = 0.f;
    for (uint i = 0; i < cellInfo.count; ++i)
    {
        uint surfelIndex = gCellIndexBuffer[cellInfo.offset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        float3 bias = worldPos - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < kSurfelRadius * kSurfelRadius)
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(gNormal[pixelPos].xyz, normal);
            if (dotN > 0)
            {
                float dist = sqrt(dist2);
                float contribution = 1.f;

                contribution *= saturate(dotN);
                contribution *= saturate(1 - dist / kSurfelRadius);
                contribution = smoothstep(0, 1, contribution);
                coverage += contribution;
            }
        }
    }

    Random::State randomState = Random::init(pixelPos, gFrameIndex);

    if (cellInfo.count < kCellSurfelLimit)
    {
        uint coverageData = 0;
        coverageData |= ((f32tof16(coverage) & 0x0000FFFF) << 16);
        coverageData |= ((Random::nextUint(randomState, 255) & 0x000000FF) << 8);
        coverageData |= ((groupThreadID.x & 0x0000000F) << 4);
        coverageData |= ((groupThreadID.y & 0x0000000F) << 0);

        InterlockedMin(groupShareMinCoverage, coverageData);
    }

    GroupMemoryBarrierWithGroupSync();

    gCoverage[tilePos] = groupShareMinCoverage;
}

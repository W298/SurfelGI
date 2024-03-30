import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

cbuffer CB
{
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint2 gTileSize;
    uint32_t gSurfelLimit;
    float gSurfelRadius;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;

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

    uint2 tilePos = dispatchThreadId.xy / gTileSize;
    uint2 pixelPos = dispatchThreadId.xy;

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    float3 unProjectedPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    float coverage = 0.f;
    for (uint s = 0; s < gSurfelLimit; s++)
    {
        Surfel surfel = gSurfelBuffer[s];

        if (!surfel.valid)
            continue;

        float3 bias = unProjectedPos - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < gSurfelRadius * gSurfelRadius)
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(gNormal[pixelPos].xyz, normal);
            if (dotN > 0)
            {
                float dist = sqrt(dist2);
                float contribution = 1.f;

                contribution *= saturate(dotN);
                contribution *= saturate(1 - dist / gSurfelRadius);
                contribution = smoothstep(0, 1, contribution);
                coverage += contribution;
            }
        }
    }

    uint coverageData = 0;
    coverageData |= ((f32tof16(coverage) & 0x0000FFFF) << 16);
    coverageData |= ((groupThreadID.x & 0x0000000F) << 4);
    coverageData |= ((groupThreadID.y & 0x0000000F) << 0);

    InterlockedMin(groupShareMinCoverage, coverageData);

    GroupMemoryBarrierWithGroupSync();

    gCoverage[tilePos] = groupShareMinCoverage;
}

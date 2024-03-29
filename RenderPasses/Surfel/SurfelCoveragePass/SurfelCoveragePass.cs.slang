import RenderPasses.Surfel.SurfelTypes;

cbuffer CB
{
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint2 gTileSize;
    uint32_t gSurfelLimit;
    float gSurfelRadius;

    RWStructuredBuffer<Surfel> gSurfelBuffer;
}

Texture2D<float32_t> gDepth;
Texture2D<float4> gNormal;

RWTexture2D<uint> gCoverage;

float3 unProject(float2 uv, float32_t depth)
{
    float x = uv.x * 2 - 1;
    float y = (1 - uv.y) * 2 - 1;
    float4 pos = mul(gInvViewProj, float4(x, y, depth, 1));

    return pos.xyz / pos.w;
}

float3 unProject(uint2 pixel, float32_t depth)
{
    return unProject(pixel * gInvResolution, depth);
}

groupshared uint groupShareMinCoverage;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 groupThreadID : SV_GroupThreadID)
{
    if (groupIndex == 0)
    {
        groupShareMinCoverage = ~0;
    }
    GroupMemoryBarrierWithGroupSync();

    uint2 tilePixel = dispatchThreadId.xy / gTileSize;
    uint2 targetPixel = dispatchThreadId.xy;

    float32_t depth = gDepth[targetPixel];
    if (depth == 1)
        return;

    float3 unProjectedPos = unProject(targetPixel, depth);

    float coverage = 0.h;
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

            float dotN = dot(gNormal[targetPixel].xyz, normal);
            if (dotN > 0)
            {
                float dist = sqrt(dist2);
                float contribution = 1.h;

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

    gCoverage[tilePixel] = groupShareMinCoverage;
}

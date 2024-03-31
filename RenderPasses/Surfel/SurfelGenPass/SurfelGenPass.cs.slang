import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

cbuffer CB
{
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint2 gTileSize;
    uint32_t gSurfelLimit;
    float gSurfelRadius;
    uint32_t gFrameIndex;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;

Texture2D<float32_t> gDepth;
Texture2D<float4> gNormal;
Texture2D<uint> gCoverage;

RWTexture2D<float4> gOutput;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID)
{
    uint2 tilePos = dispatchThreadId.xy / gTileSize;
    uint2 pixelPos = dispatchThreadId.xy;

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    uint coverageData = gCoverage[tilePos];
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

    float3 unProjectedPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    if (groupThreadID.x == x && groupThreadID.y == y && coverage < 0.01f)
    {
        const float chance = pow(depth, 8);
        Random::State randomState = Random::init(pixelPos, gFrameIndex);

        if (Random::nextFloat(randomState) < chance)
        {
            uint aliveCount;
            gSurfelStatus.InterlockedAdd(0, 1, aliveCount);

            if (aliveCount < gSurfelLimit)
            {
                float3 normal = gNormal[pixelPos].xyz;
                float3 randomColor = Random::nextFloat3(randomState);

                Surfel newSurfel = { unProjectedPos, normal, randomColor, true };
                gSurfelBuffer[aliveCount] = newSurfel;
            }
        }
    }

    // Visualize
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
                gOutput[pixelPos] = float4(surfel.color, 1);
                return;
            }
        }
    }
}

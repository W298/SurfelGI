import RenderPasses.Surfel.SurfelTypes;

cbuffer CB
{
    uint2 gResolution;
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint2 gTileSize;
    uint32_t gSurfelLimit;
    float gSurfelRadius;

    RWStructuredBuffer<Surfel> gSurfelBuffer;
}

Texture2D<float32_t> gDepth;
Texture2D<float4> gNormal;
Texture2D<float4> gRaster;

RWTexture2D<uint16_t> gCoverage;

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

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 rightTopPixel = dispatchThreadId.xy * gTileSize;

    [unroll]
    for (uint x = 0; x < 16; x++)
    {
        for (uint y = 0; y < 16; y++)
        {
            uint2 targetPixel = rightTopPixel + uint2(x, y);
            float32_t depth = gDepth[targetPixel];
            if (depth == 1)
                continue;

            float3 unProjectedPos = unProject(targetPixel, depth);

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
                        gCoverage[dispatchThreadId.xy] = 1;
                    }
                }
            }
        }
    }
}

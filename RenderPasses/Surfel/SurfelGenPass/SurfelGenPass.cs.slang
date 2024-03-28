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
Texture2D<uint16_t> gCoverage;
Texture2D<float4> gRaster;

RWTexture2D<float4> gOutput;

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

    Surfel surfel = gSurfelBuffer[0];

    [unroll]
    for (uint x = 0; x < 16; x++)
    {
        for (uint y = 0; y < 16; y++)
        {
            uint2 targetPixel = rightTopPixel + uint2(x, y);
            float32_t depth = gDepth[targetPixel];

            if (gCoverage[dispatchThreadId.xy] == 1)
                gOutput[targetPixel] = float4(1, 0, 0, 1);
            else
                gOutput[targetPixel] = gRaster[targetPixel];
        }
    }
}

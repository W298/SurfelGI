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
Texture2D<uint> gCoverage;
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
    uint2 tilePixel = dispatchThreadId.xy / gTileSize;
    uint2 targetPixel = dispatchThreadId.xy;

    uint coverageData = gCoverage[tilePixel];
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

    if (coverageData != 0)
        gOutput[targetPixel] = float4(coverage, x / 16.f, y / 16.f, 1);
    else
        gOutput[targetPixel] = gRaster[targetPixel];
}

cbuffer PerFrameCB
{
    uint2 gResolution;
    float2 gInvResolution;
    float4x4 gInvViewProj;
}

Texture2D<float32_t> gDepth;
Texture2D<float4> gRaster;
RWTexture2D<float4> gOutput;

float3 getWorldPos(float2 uv, float32_t depth)
{
    float x = uv.x * 2 - 1;
    float y = (1 - uv.y) * 2 - 1;
    float4 pos = mul(gInvViewProj, float4(x, y, depth, 1));

    return pos.xyz / pos.w;
}

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupId: SV_GroupID)
{
    // float2 groupUV = groupId.xy * (gInvResolution * 16.0f);

    uint2 pixelPos = dispatchThreadId.xy;
    float2 uv = pixelPos * gInvResolution;
    float32_t depth = gDepth[pixelPos];

    if (depth == 1)
    {
        gOutput[pixelPos] = float4(0, 0, 0, 1);
        return;
    }

    float3 worldPos = getWorldPos(uv, depth);
    gOutput[pixelPos] = float4(worldPos, 1);
}

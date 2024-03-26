Texture2D<float4> gDepth;
Texture2D<float4> gRaster;
RWTexture2D<float4> gOutput;

cbuffer PerFrameCB
{
    uint2 gResolution;
    float2 gInvResolution;
}

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupId: SV_GroupID)
{
    uint2 pixelPos = dispatchThreadId.xy;
    float2 uv = pixelPos * gInvResolution;
    float2 groupUV = groupId.xy * (gInvResolution * 16.0f);

    gOutput[pixelPos] = float4(groupUV, 0, 1);
}

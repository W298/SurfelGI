#include "../Random.hlsli"
#include "../SurfelTypes.hlsli"
#include "../SurfelUtils.hlsli"

Texture2D<float4> gInstanceIDVisual;
Texture2D<float4> gSurfel;

RWTexture2D<float4> gDebug;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 groupThreadID : SV_GroupThreadID)
{
    uint2 pixelPos = dispatchThreadId.xy;

    float3 surfelColor = gSurfel[pixelPos].xyz;
    float3 instanceColor = gInstanceIDVisual[pixelPos].xyz;

    float strength = clamp(length(surfelColor), 0.01f, 0.99f);
    float3 combine = 0.95f * (instanceColor * strength) + 0.05f * surfelColor;

    gDebug[pixelPos] = float4(combine, 1);
}

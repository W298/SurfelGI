RWTexture2D<float4> gReflectionHitInfo;
RWTexture2D<float4> gReflectionDirection;
RWTexture2D<float4> gBlurredReflectionLighting;
RWTexture2D<float4> gDiffuseLighting;

RWTexture2D<float4> gFinalResult;

[numthreads(32, 32, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 pixelPos = dispatchThreadId.xy;

    uint4 packedRefHitInfo = gReflectionHitInfo[pixelPos];
    const bool isRefHitValid = (packedRefHitInfo[0] >> 31) != 0;
    const float3 reflectionDir = gReflectionDirection[pixelPos].xyz;

    gFinalResult[pixelPos] = gDiffuseLighting[pixelPos];

    if (isRefHitValid || length(reflectionDir) > 0.f)
    {
        gFinalResult[pixelPos] += gBlurredReflectionLighting[pixelPos];
    }
}

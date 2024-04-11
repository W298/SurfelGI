#include "../Random.hlsli"
#include "../SurfelTypes.hlsli"
#include "../SurfelUtils.hlsli"

RWTexture2D<float4> gDebug;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupdId: SV_GroupID)
{
    gDebug[dispatchThreadId.xy] = float4((pseudocolor(groupdId.x) * pseudocolor(groupdId.y) * pseudocolor(groupdId.z)), 1);
}

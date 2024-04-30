import Scene.Scene;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

RWByteAddressBuffer gSurfelCounter;

// Will be moved at Update Pass later for optimzation.
[numthreads(32, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint validSurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::ValidSurfel);
    if (dispatchThreadId.x >= validSurfelCount)
        return;

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    // Moving average radiance.
    for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
    {
        float3 rayRadiance = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex].radiance;
        float weight = 1.0f / ++surfel.accumulated;

        surfel.radiance = lerp(surfel.radiance, rayRadiance, weight);
    }

    // Write back to buffer.
    gSurfelBuffer[surfelIndex] = surfel;
}

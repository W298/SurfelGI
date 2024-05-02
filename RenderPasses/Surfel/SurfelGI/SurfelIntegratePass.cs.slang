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

    // We use lambertian for surfel radiance, it follows lambert's cosine law.
    // surfel radiance = 1 / PI * integral [ Li * cos(theta) ]
    // surfel radiance (with sampling) = 1 / N * sum[ Li * cos(theta) ]
    float3 surfelRadiance = float3(0.f);
    for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
    {
        float3 Lr = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex].radiance;
        float3 dir = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex].direction;

        surfelRadiance += Lr * dot(dir, surfel.normal);
    }
    surfelRadiance /= surfel.rayCount;

    // Moving average radiance.
    float weight = 1.0f / ++surfel.accumulated;
    surfel.radiance = lerp(surfel.radiance, surfelRadiance, weight);

    // Write back to buffer.
    gSurfelBuffer[surfelIndex] = surfel;
}

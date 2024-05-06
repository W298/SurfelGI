import Scene.Scene;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;
import RenderPasses.Surfel.SurfelGI.MultiscaleMeanEstimator;

#define USE_IRRADIANCE_SHARING 0

cbuffer CB
{
    float gShortMeanWindow;
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

RWByteAddressBuffer gSurfelCounter;
ByteAddressBuffer gSurfelConfig;

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

    // Irradiance sharing.
#if USE_IRRADIANCE_SHARING
    {
        float4 sharedRadiance = float4(0.f);
        SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);
        int3 cellPos = getCellPos(surfel.position, gScene.camera.getPosition(), config.cellUnit);
        if (isCellValid(cellPos))
        {
            const float3 centerPos = surfel.position;
            const float3 centerNormal = surfel.normal;

            uint flattenIndex = getFlattenCellIndex(cellPos);
            CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

            for (uint i = 0; i < cellInfo.surfelCount; ++i)
            {
                uint neiSurfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
                Surfel neiSurfel = gSurfelBuffer[neiSurfelIndex];

                float3 bias = centerPos - neiSurfel.position;
                float dist2 = dot(bias, bias);
                float affectRadius = config.cellUnit * sqrt(3);

                if (dist2 < pow(affectRadius, 2))
                {
                    float dotN = dot(neiSurfel.normal, centerNormal);
                    if (dotN > 0)
                    {
                        float dist = sqrt(dist2);
                        float contribution = 1.f;

                        contribution *= saturate(dotN);
                        contribution *= saturate(1 - dist / affectRadius);
                        contribution = smoothstep(0, 1, contribution);

                        sharedRadiance += float4(neiSurfel.radiance, 1.f) * contribution;
                    }
                }
            }

            if (sharedRadiance.w > 0)
            {
                sharedRadiance.xyz /= sharedRadiance.w;
                surfelRadiance = surfelRadiance + sharedRadiance.xyz;
            }
        }
    }
#endif

    // Update surfel radiance using Multiscale Mean Estimator.
    float3 mean = MSME(surfelRadiance, surfel.msmeData, gShortMeanWindow);
    surfel.radiance = mean;

    // Increase sample count.
    surfel.sampleCount += surfel.rayCount;

    // Write back to buffer.
    gSurfelBuffer[surfelIndex] = surfel;
}

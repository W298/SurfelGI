#include "Utils/Math/MathConstants.slangh"

import Scene.Scene;
import Utils.Color.ColorHelpers;
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

RWTexture2D<float> gIrradianceMap;

// Will be moved at Update Pass later for optimzation.
[numthreads(32, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint validSurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::ValidSurfel);
    if (dispatchThreadId.x >= validSurfelCount)
        return;

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    uint2 irrMapBase = uint2(
        surfelIndex % (kIrradianceMapRes.x / kIrradianceMapUnit.x),
        surfelIndex / (kIrradianceMapRes.x / kIrradianceMapUnit.y)
    );
    irrMapBase *= kIrradianceMapUnit;

    float3 surfelRadiance = float3(0.f);
    for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
    {
        const SurfelRayResult rayResult = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex];

        float3 Lr = rayResult.radiance;
        float3 dirLocal = rayResult.dirLocal;
        float3 dirWorld = rayResult.dirWorld;
        float pdf = rayResult.pdf;

        float2 uv = octEncode(normalize(dirLocal));
        uint2 irrMapOffset = kIrradianceMapHalfUnit + int2(
            sign(uv.x) * round(abs(uv.x * kIrradianceMapHalfUnit.x)),
            sign(uv.y) * round(abs(uv.y * kIrradianceMapHalfUnit.y))
        );
        uint2 irrMapCoord = irrMapBase + irrMapOffset;

        // Write radiance of ray at texture for ray-guiding.
        // Mininum boundary is 1e-3f, because pdf should not be 0 for importance sampling.
        float k = 1e-2f;
        float delta = luminance(Lr) - gIrradianceMap[irrMapCoord];
        gIrradianceMap[irrMapCoord] = max(1e-3f, gIrradianceMap[irrMapCoord] + k * delta);

        // Calculate incident radiance by using importance sampling.
        surfelRadiance += Lr * dot(dirWorld, surfel.normal) * ((1.f / (16 * M_PI)) / max(1e-12f, pdf));
    }

    surfelRadiance /= surfel.rayCount;

    float sumLuminance = 0.f;
    bool hasHole = false;

    // Sum luminances and check if irradiance map of surfel has hole (not sampled yet).
    for (uint y = 0; y < kIrradianceMapUnit.y; ++y)
    {
        for (uint x = 0; x < kIrradianceMapUnit.x; ++x)
        {
            const float l = gIrradianceMap[irrMapBase + uint2(x, y)];
            sumLuminance += l;
            if (!hasHole && step(l, 1e-12f))
                hasHole = true;
        }
    }

    surfel.sumLuminance = sumLuminance;
    surfel.hasHole = hasHole;

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

    // Reduce life.
    surfel.life--;

    // Write back to buffer.
    gSurfelBuffer[surfelIndex] = surfel;
}

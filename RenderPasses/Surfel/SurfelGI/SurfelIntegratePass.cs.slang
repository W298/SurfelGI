#include "Utils/Math/MathConstants.slangh"

import Scene.Scene;
import Utils.Color.ColorHelpers;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;
import RenderPasses.Surfel.SurfelGI.StaticParams;
import RenderPasses.Surfel.SurfelGI.MultiscaleMeanEstimator;

cbuffer CB
{
    float gShortMeanWindow;
    float3 gCameraPos;
    float gVarianceSensitivity;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

RWByteAddressBuffer gSurfelCounter;

RWTexture2D<float> gIrradianceMap;
RWTexture2D<float2> gSurfelDepthRW;
Texture2D<float2> gSurfelDepth;

SamplerState gSurfelDepthSampler;

// Will be moved at Update Pass later for optimzation.
[numthreads(32, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint validSurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::ValidSurfel);
    if (dispatchThreadId.x >= validSurfelCount)
        return;

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    // If no ray is allocated, exit.
    if (surfel.rayCount == 0)
        return;

    // Irrdiance map left top coordinate.
    uint2 irrMapLT = uint2(
        surfelIndex % (kIrradianceMapRes.x / kIrradianceMapUnit.x),
        surfelIndex / (kIrradianceMapRes.x / kIrradianceMapUnit.y)
    );
    irrMapLT *= kIrradianceMapUnit;

    // Surfel depth texture left top coordinate.
    uint2 surfelDepthLT = uint2(
        surfelIndex % (kSurfelDepthTextureRes.x / kSurfelDepthTextureUnit.x),
        surfelIndex / (kSurfelDepthTextureRes.x / kSurfelDepthTextureUnit.y)
    );
    surfelDepthLT *= kSurfelDepthTextureUnit;

    float3 surfelRadiance = float3(0.f);
    for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
    {
        const SurfelRayResult rayResult = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex];

        float3 Lr = rayResult.radiance;
        float3 dirLocal = rayResult.dirLocal;
        float3 dirWorld = rayResult.dirWorld;
        float pdf = rayResult.pdf;
        float surfelDepth = (rayResult.firstRayLength > 0) ? clamp(rayResult.firstRayLength, 0, surfel.radius) : surfel.radius;

        // Encode ray direction.
        float2 uv = octEncode(normalize(dirLocal));

#ifdef USE_RAY_GUIDING

        // Write luminance at irradiance map.
        uint2 irrMapOffset = kIrradianceMapHalfUnit + int2(
            sign(uv.x) * round(abs(uv.x * kIrradianceMapHalfUnit.x)),
            sign(uv.y) * round(abs(uv.y * kIrradianceMapHalfUnit.y))
        );
        uint2 irrMapCoord = irrMapLT + irrMapOffset;

        // Write radiance of ray at texture for ray-guiding.
        // Mininum boundary is 1e-3f, because pdf should not be 0 for importance sampling.
        float k = 1e-2f;
        float delta = luminance(Lr) - gIrradianceMap[irrMapCoord];
        gIrradianceMap[irrMapCoord] = max(1e-3f, gIrradianceMap[irrMapCoord] + k * delta);

#else  // USE_RAY_GUIDING
#endif // USE_RAY_GUIDING  

#ifdef USE_SURFEL_DEPTH

        // Write surfel depth.
        uint2 surfelDepthTextureOffset = kSurfelDepthTextureHalfUnit + int2(
            sign(uv.x) * round(abs(uv.x * (kSurfelDepthTextureHalfUnit.x - 1))),
            sign(uv.y) * round(abs(uv.y * (kSurfelDepthTextureHalfUnit.y - 1)))
        );
        uint2 surfelDepthTextureCoord = surfelDepthLT + surfelDepthTextureOffset;

        float2 signedUV = ((int2)surfelDepthTextureOffset - kSurfelDepthTextureHalfUnit) / (kSurfelDepthTextureHalfUnit - int2(1, 1));
        float3 texelDir = octDecode(signedUV);
        float depthWeight = saturate(dot(dirLocal, texelDir));

        float k2 = 1e-2f;
        float2 delta2 = float2(surfelDepth, pow(surfelDepth, 2)) - gSurfelDepthRW[surfelDepthTextureCoord];
        gSurfelDepthRW[surfelDepthTextureCoord] = gSurfelDepthRW[surfelDepthTextureCoord] + k2 * delta2 * depthWeight;

#else  // USE_SURFEL_DEPTH
#endif // USE_SURFEL_DEPTH

        // Calculate incident radiance by using importance sampling.
        surfelRadiance += Lr * dot(dirWorld, surfel.normal) * ((1.f / (16 * M_PI)) / max(1e-12f, pdf));
    }

    // Average radiance.
    surfelRadiance /= surfel.rayCount;

#ifdef USE_RAY_GUIDING

    // Sum luminances and check if irradiance map of surfel has hole (not sampled yet).
    float sumLuminance = 0.f;
    bool hasHole = false;

    for (uint y = 0; y < kIrradianceMapUnit.y; ++y)
    {
        for (uint x = 0; x < kIrradianceMapUnit.x; ++x)
        {
            const float l = gIrradianceMap[irrMapLT + uint2(x, y)];
            sumLuminance += l;
            if (!hasHole && step(l, 1e-12f))
                hasHole = true;
        }
    }

    surfel.sumLuminance = sumLuminance;
    surfel.hasHole = hasHole;

#else  // USE_RAY_GUIDING
#endif // USE_RAY_GUIDING

#ifdef USE_SURFEL_DEPTH

    // Write border.
    for (uint x = 1; x < kSurfelDepthTextureUnit.x - 1; ++x)
    {
        gSurfelDepthRW[surfelDepthLT + uint2(x, 0)] = gSurfelDepthRW[surfelDepthLT + uint2(x, 1)];
        gSurfelDepthRW[surfelDepthLT + uint2(x, kSurfelDepthTextureUnit.y - 1)] =
            gSurfelDepthRW[surfelDepthLT + uint2(x, kSurfelDepthTextureUnit.y - 2)];
    }
    for (uint y = 1; y < kSurfelDepthTextureUnit.y - 1; ++y)
    {
        gSurfelDepthRW[surfelDepthLT + uint2(0, y)] = gSurfelDepthRW[surfelDepthLT + uint2(1, y)];
        gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 1, y)] =
            gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 2, y)];
    }

    // Write corner.
    gSurfelDepthRW[surfelDepthLT + uint2(0, 0)] = (
        gSurfelDepthRW[surfelDepthLT + uint2(0, 1)] +
        gSurfelDepthRW[surfelDepthLT + uint2(1, 0)]
    ) / 2.f;

    gSurfelDepthRW[surfelDepthLT + uint2(0, kSurfelDepthTextureUnit.y - 1)] = (
        gSurfelDepthRW[surfelDepthLT + uint2(0, kSurfelDepthTextureUnit.y - 2)] +
        gSurfelDepthRW[surfelDepthLT + uint2(1, kSurfelDepthTextureUnit.y - 1)]
    ) / 2.f;

    gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 1, kSurfelDepthTextureUnit.y - 1)] = (
        gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 1, kSurfelDepthTextureUnit.y - 2)] +
        gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 2, kSurfelDepthTextureUnit.y - 1)]
    ) / 2.f;

    gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 1, 0)] = (
        gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 1, 1)] +
        gSurfelDepthRW[surfelDepthLT + uint2(kSurfelDepthTextureUnit.x - 2, 0)]
    ) / 2.f;

#else  // USE_SURFEL_DEPTH
#endif // USE_SURFEL_DEPTH

#ifdef USE_IRRADIANCE_SHARING

    float4 sharedRadiance = float4(0.f);
    int3 cellPos = getCellPos(surfel.position, gCameraPos, kCellUnit);
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
            float affectRadius = kCellUnit * sqrt(2);

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

                    #ifdef USE_SURFEL_DEPTH
                    {
                        float2 uv = getSurfelDepthUV(surfelIndex, bias / dist, centerNormal);
                        float2 surfelDepth = gSurfelDepth.SampleLevel(gSurfelDepthSampler, uv, 0u);

                        float mean = surfelDepth.x;
                        float sqrMean = surfelDepth.y;

                        if (dist > mean)
                        {
                            float variance = sqrMean - pow(mean, 2);
                            contribution *= variance / (variance + pow(dist - mean, 2));
                        }
                    }
                    #else  // USE_SURFEL_DEPTH
                    #endif // USE_SURFEL_DEPTH

                    sharedRadiance += float4(neiSurfel.radiance, 1.f) * contribution;
                }
            }
        }

        if (sharedRadiance.w > 0)
        {
            sharedRadiance.xyz /= sharedRadiance.w;
            surfelRadiance = lerp(
                surfelRadiance,
                sharedRadiance.xyz,
                saturate(length(surfel.msmeData.variance) * gVarianceSensitivity)
            );
        }
    }

#else  // USE_IRRADIANCE_SHARING
#endif // USE_IRRADIANCE_SHARING

    // Update surfel radiance using Multiscale Mean Estimator.
    float3 mean = MSME(surfelRadiance, surfel.msmeData, gShortMeanWindow);
    surfel.radiance = mean;

    // Write back to buffer.
    gSurfelBuffer[surfelIndex] = surfel;
}

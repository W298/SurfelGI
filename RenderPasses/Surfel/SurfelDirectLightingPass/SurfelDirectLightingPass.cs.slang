
#include "Utils/Math/MathConstants.slangh"

import Scene.RaytracingInline;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.EnvMapSampler;
import Rendering.Lights.LightHelpers;
import Utils.Geometry.GeometryHelpers;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
    bool gUseIndirectLighting;
}

Texture2D<uint4> gPackedHitInfo;
Texture2D<float4> gIndirectLighting;
RWTexture2D<float4> gOutput;

float3 evalDirectAnalytic(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    // Pick one of the analytic light sources randomly with equal probability.
    const uint lightIndex = min(uint(sampleNext1D(sg) * lightCount), lightCount - 1);
    float invPdf = lightCount; // Light selection pdf = 1.0 / lightCount.

    // Sample local light source.
    AnalyticLightSample ls;
    if (!sampleLight(sd.posW, gScene.getLight(lightIndex), sg, ls))
        return float3(0.f);

    // Reject sample if not in the hemisphere of a BSDF lobe.
    const uint lobeTypes = mi.getLobeTypes(sd);
    const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
    const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
    float NdotL = dot(sd.getOrientedFaceNormal(), ls.dir);
    if ((NdotL <= kMinCosTheta && !hasTransmission) || (NdotL >= -kMinCosTheta && !hasReflection))
        return float3(0.f);

    // Get origin with offset applied in direction of the geometry normal to avoid self-intersection.
    const float3 origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);

    // Test visibility by tracing a shadow ray.
    Ray ray;
    ray.origin = origin;
    ray.dir = ls.dir;
    ray.tMin = 0.f;
    ray.tMax = ls.distance;

    SceneRayQuery<0> sceneRayQuery;

    HitInfo hit;
    float hitT;
    sceneRayQuery.traceRay(ray, hit, hitT, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff);

    if (hit.isValid())
        return float3(0.f);

    // Evaluate contribution.
    return mi.eval(sd, ls.dir, sg) * ls.Li * invPdf;
}

float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    float3 acc = float3(0.f);
    for (int i = 0; i < lightCount; ++i)
    {
        AnalyticLightSample ls;
        if (!sampleLight(sd.posW, gScene.getLight(i), sg, ls))
            continue;

        const uint lobeTypes = mi.getLobeTypes(sd);
        const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
        const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
        float NdotL = dot(sd.getOrientedFaceNormal(), ls.dir);
        if ((NdotL <= kMinCosTheta && !hasTransmission) || (NdotL >= -kMinCosTheta && !hasReflection))
            continue;

        Ray ray;
        ray.origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
        ray.dir = ls.dir;
        ray.tMin = 0.f;
        ray.tMax = ls.distance;

        SceneRayQuery<0> sceneRayQuery;

        HitInfo hit;
        float hitT;
        sceneRayQuery.traceRay(ray, hit, hitT, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff);

        if (!hit.isValid())
            acc += mi.eval(sd, ls.dir, sg) * ls.Li;
    }

    return acc;
}

[numthreads(32, 32, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupdId: SV_GroupID)
{
    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 pixelPos = dispatchThreadId.xy;
    uint4 pack = gPackedHitInfo[pixelPos];

    if (pack.w == 0)
    {
        const float3 ray = gScene.camera.computeRayPinhole(pixelPos, gResolution).dir;
        gOutput[pixelPos] = float4(gScene.envMap.eval(ray), 1);
    }
    else
    {
        TriangleHit hit = TriangleHit(pack);

        VertexData v = gScene.getVertexData(hit);
        let lod = ExplicitLodTextureSampler(0.f);

        float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
        ShadingData sd = gScene.materials.prepareShadingData(v, gScene.getMaterialID(hit.instanceID), viewDir, lod);
        IMaterialInstance mi = gScene.materials.getMaterialInstance(sd, lod);

        SampleGenerator sg = SampleGenerator(pixelPos, gFrameIndex);

        float3 finalColor = evalAnalyticLight(sd, mi, sg);

        if (gUseIndirectLighting)
        {
            BSDFProperties prop = mi.getProperties(sd);
            finalColor += prop.diffuseReflectionAlbedo * M_PI * dot(v.normalW, viewDir) * gIndirectLighting[pixelPos].xyz;
        }

        gOutput[pixelPos] = float4(finalColor, 1.f);
    }
}

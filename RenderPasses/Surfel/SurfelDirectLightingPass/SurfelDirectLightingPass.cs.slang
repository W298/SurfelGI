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
    bool gRenderDirectLighting;
    bool gRenderIndirectLighting;
}

Texture2D<uint4> gPackedHitInfo;
Texture2D<float4> gIndirectLighting;
RWTexture2D<float4> gOutput;

// [Sample ALL light sources]
float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    float3 Lr = float3(0.f);
    for (uint i = 0; i < lightCount; ++i)
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

        // Trace shadow ray to check light source is visible or not.
        HitInfo hit;
        {
            SceneRayQuery<0> sceneRayQuery;
            float hitT;

            Ray ray;
            ray.origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
            ray.dir = ls.dir;
            ray.tMin = 0.f;
            ray.tMax = ls.distance;

            sceneRayQuery.traceRay(ray, hit, hitT, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff);
        }

        if (!hit.isValid())
            Lr += mi.eval(sd, ls.dir, sg) * ls.Li;
    }

    return Lr;
}

[numthreads(32, 32, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupdId: SV_GroupID)
{
    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 pixelPos = dispatchThreadId.xy;
    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);

    // If hit is miss, draw environment map.
    if (!hitInfo.isValid())
    {
        const float3 ray = gScene.camera.computeRayPinhole(pixelPos, gResolution).dir;
        gOutput[pixelPos] = float4(gScene.envMap.eval(ray), 1);
    }
    else
    {
        TriangleHit triangleHit = hitInfo.getTriangleHit();
        VertexData v = gScene.getVertexData(triangleHit);
        float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
        uint materialID = gScene.getMaterialID(triangleHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);
        ShadingData sd = gScene.materials.prepareShadingData(v, materialID, viewDir, lod);
        let mi = gScene.materials.getMaterialInstance(sd, lod);

        SampleGenerator sg = SampleGenerator(pixelPos, gFrameIndex);
        
        float3 finalGather = float3(0.f);

        const float3 directLighting = evalAnalyticLight(sd, mi, sg);
        const float3 indirectLighting = gIndirectLighting[pixelPos].xyz;

        if (gRenderDirectLighting && gRenderIndirectLighting)
        {
            // So far, specular is not supported.

            // weight = f(wi, wo) * dot(wo, n) / pdf(wo).
            // Becuase it is lambertian,
            // - BRDF term is albedo / PI,
            // - pdf is 1 / PI,
            // dot(wo, n) is already calculated when accumulating surfel radiance.
            // so, weight is equal to albedo.

            BSDFProperties props = mi.getProperties(sd);
            float3 weight = props.diffuseReflectionAlbedo;
            finalGather = directLighting + weight * indirectLighting;
        }
        else
        {
            finalGather = gRenderDirectLighting ? directLighting : gRenderIndirectLighting ? indirectLighting : float3(0.f);
        }

        gOutput[pixelPos] = float4(finalGather, 1.f);
    }
}

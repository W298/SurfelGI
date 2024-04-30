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

float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    float3 acc = float3(0.f);
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
    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);

    // If hit is miss, show environment map.
    if (!hitInfo.isValid())
    {
        const float3 ray = gScene.camera.computeRayPinhole(pixelPos, gResolution).dir;
        gOutput[pixelPos] = float4(gScene.envMap.eval(ray), 1);
    }
    else
    {
        TriangleHit triangleHit = hitInfo.getTriangleHit();
        VertexData v = gScene.getVertexData(triangleHit);
        let lod = ExplicitLodTextureSampler(0.f);

        float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
        ShadingData sd = gScene.materials.prepareShadingData(v, gScene.getMaterialID(triangleHit.instanceID), viewDir, lod);
        let mi = gScene.materials.getMaterialInstance(sd, lod);

        SampleGenerator sg = SampleGenerator(pixelPos, gFrameIndex);
        
        float3 finalColor = float3(0.f);

        const float3 directLighting = evalAnalyticLight(sd, mi, sg);
        const float3 indirectLighting = gIndirectLighting[pixelPos].xyz;
        
        if (gRenderDirectLighting && gRenderIndirectLighting)
        {
            finalColor = directLighting + mi.getProperties(sd).diffuseReflectionAlbedo * M_PI * dot(v.normalW, viewDir) * indirectLighting;
        }
        else
        {
            finalColor = gRenderDirectLighting ? directLighting : gRenderIndirectLighting ? indirectLighting : float3(0.f);
        }

        gOutput[pixelPos] = float4(finalColor, 1.f);
    }
}

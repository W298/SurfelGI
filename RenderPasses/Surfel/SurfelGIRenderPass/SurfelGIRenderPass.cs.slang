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
    bool gRenderReflection;
}

Texture2D<uint4> gHitInfo;
Texture2D<uint4> gReflectionHitInfo;
Texture2D<float4> gReflectionDirection;
Texture2D<float4> gDiffuseIndirectLighting;
Texture2D<float4> gReflectionIndirectLighting;

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
    HitInfo hitInfo = HitInfo(gHitInfo[pixelPos]);

    // If hit is miss, draw environment map.
    if (!hitInfo.isValid())
    {
        const float3 ray = gScene.camera.computeRayPinhole(pixelPos, gResolution).dir;
        gOutput[pixelPos] = float4(gScene.envMap.eval(ray), 1);

        return;
    }

    SampleGenerator sg = SampleGenerator(pixelPos, gFrameIndex);

    float3 reflectionLighting = float3(0.f);
    {
        HitInfo refHitInfo = HitInfo(gReflectionHitInfo[pixelPos]);
        const float3 reflectionDir = gReflectionDirection[pixelPos].xyz;

        // If reflection hit is miss, draw environment map.
        if (!refHitInfo.isValid())
        {
            const float3 refRayDir = -reflectionDir;
            reflectionLighting = gScene.envMap.eval(refRayDir);
        }
        else
        {
            TriangleHit triangleHit = refHitInfo.getTriangleHit();
            VertexData v = gScene.getVertexData(triangleHit);
            uint materialID = gScene.getMaterialID(triangleHit.instanceID);
            let lod = ExplicitLodTextureSampler(0.f);
            ShadingData sd = gScene.materials.prepareShadingData(v, materialID, reflectionDir, lod);
            let mi = gScene.materials.getMaterialInstance(sd, lod);

            BSDFProperties props = mi.getProperties(sd);
            float3 weight = props.diffuseReflectionAlbedo;

            if (gRenderDirectLighting)
                reflectionLighting += evalAnalyticLight(sd, mi, sg);

            if (gRenderIndirectLighting)
                reflectionLighting += weight * gReflectionIndirectLighting[pixelPos].xyz;

            reflectionLighting += mi.getProperties(sd).emission;
        }
    }

    float3 finalGather = float3(0.f);
    {
        TriangleHit triangleHit = hitInfo.getTriangleHit();
        VertexData v = gScene.getVertexData(triangleHit);
        float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
        uint materialID = gScene.getMaterialID(triangleHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);
        ShadingData sd = gScene.materials.prepareShadingData(v, materialID, viewDir, lod);
        let mi = gScene.materials.getMaterialInstance(sd, lod);

        const float3 directLighting = evalAnalyticLight(sd, mi, sg);
        const float3 diffuseIndirectLighting = gDiffuseIndirectLighting[pixelPos].xyz;

        BSDFProperties props = mi.getProperties(sd);
        float3 weight = props.diffuseReflectionAlbedo;

        if (gRenderDirectLighting)
            finalGather += directLighting;

        if (gRenderIndirectLighting)
            finalGather += weight * diffuseIndirectLighting;

        if (gRenderReflection)
            finalGather += reflectionLighting;

        finalGather += mi.getProperties(sd).emission;
    }

    gOutput[pixelPos] = float4(finalGather, 1.f);
}

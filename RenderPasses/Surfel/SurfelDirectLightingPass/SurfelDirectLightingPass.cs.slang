import Scene.Raster;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.EnvMapSampler;
import Rendering.Lights.LightHelpers;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
}

Texture2D<uint4> gPackedHitInfo;
RWTexture2D<float4> gOutput;

float3 evalAnalyticLight2(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    float3 accumulate = 0.f;
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

        accumulate += mi.eval(sd, ls.dir, sg) * ls.Li;
    }

    return accumulate;
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

        gOutput[pixelPos] = float4(evalAnalyticLight2(sd, mi, sg), 1);
    }
}

import Scene.Raster;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.EnvMapSampler;
import Rendering.Lights.LightHelpers;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
}

EnvMapSampler envMapSampler;

VSOut vsMain(VSIn vIn)
{
    return defaultVS(vIn);
}

float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    const uint lightIndex = min(uint(sampleNext1D(sg) * lightCount), lightCount - 1);
    float invPdf = lightCount;

    AnalyticLightSample ls;
    if (!sampleLight(sd.posW, gScene.getLight(lightIndex), sg, ls))
        return float3(0.f);

    const uint lobeTypes = mi.getLobeTypes(sd);
    const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
    const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
    float NdotL = dot(sd.getOrientedFaceNormal(), ls.dir);
    if ((NdotL <= kMinCosTheta && !hasTransmission) || (NdotL >= -kMinCosTheta && !hasReflection))
        return float3(0.f);

    return mi.eval(sd, ls.dir, sg) * ls.Li * invPdf;
}

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

float4 psMain(VSOut vOut, uint triangleIndex: SV_PrimitiveID) : SV_TARGET
{
    float3 faceNormal = gScene.getFaceNormalW(vOut.instanceID, triangleIndex);
    VertexData v = prepareVertexData(vOut, faceNormal);
    let lod = ExplicitLodTextureSampler(0.f);

    float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
    ShadingData sd = gScene.materials.prepareShadingData(v, vOut.materialID, viewDir, lod);
    IMaterialInstance mi = gScene.materials.getMaterialInstance(sd, lod);

    float3 clipPosition = vOut.posH.xyz / vOut.posH.w;
    clipPosition.xy += 1.0f;
    clipPosition.xy /= 2.0f;
    uint2 pixelPos = uint2(clipPosition.x * gResolution.x, clipPosition.y * gResolution.y);

    SampleGenerator sg = SampleGenerator(pixelPos, gFrameIndex);

    return float4(evalAnalyticLight2(sd, mi, sg), 1.f);
}

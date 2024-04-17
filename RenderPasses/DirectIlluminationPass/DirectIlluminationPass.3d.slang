import Scene.Raster;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;

cbuffer CB
{
    uint2 gResolution;
    uint gFrameIndex;
}

VSOut vsMain(VSIn vIn)
{
    return defaultVS(vIn);
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

    AnalyticLightSample ls;
    if (!sampleDirectionalLight(sd.posW, gScene.getLight(0), ls))
        return float4(0);

    const uint lobeTypes = mi.getLobeTypes(sd);
    const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
    const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
    float NdotL = dot(sd.getOrientedFaceNormal(), ls.dir);
    if ((NdotL <= kMinCosTheta && !hasTransmission) || (NdotL >= -kMinCosTheta && !hasReflection))
        return float4(0);

    return float4(mi.eval(sd, ls.dir, sg) * ls.Li * 1, 1);
}

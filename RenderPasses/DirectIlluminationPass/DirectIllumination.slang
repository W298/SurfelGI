import Scene.Raster;

cbuffer PerFrameCB
{
    float4 gColor;
};

VSOut vsMain(VSIn vIn)
{
    return defaultVS(vIn);
}

float4 psMain(VSOut vOut, uint triangleIndex: SV_PrimitiveID) : SV_TARGET
{
    float3 faceNormal = gScene.getFaceNormalW(vOut.instanceID, triangleIndex);
    VertexData v = prepareVertexData(vOut, faceNormal);
    ImplicitLodTextureSampler lod = ImplicitLodTextureSampler();

    uint numLights = gScene.getLightCount();
    float3 lightDir = gScene.getLight(0).dirW;

    float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
    ShadingData sd = gScene.materials.prepareShadingData(v, vOut.materialID, viewDir, lod);

    IMaterialInstance mi = gScene.materials.getMaterialInstance(sd, lod, 0);
    BSDFProperties bsdfProperties = mi.getProperties(sd);

    float3 diffuseAlbedo = bsdfProperties.diffuseReflectionAlbedo;
    float3 specularAlbedo = bsdfProperties.specularReflectionAlbedo;

    float3 diffuse = saturate(dot(v.normalW, -lightDir)) * diffuseAlbedo;

    float3 r = normalize(2 * v.normalW * dot(v.normalW, -lightDir) + lightDir);
    float3 c = normalize(gScene.camera.getPosition() - v.posW);
    float3 specular = pow(saturate(dot(r, c)), 1.2f) * specularAlbedo;

    float3 ambient = diffuseAlbedo * float3(0.02f, 0.02f, 0.02f);

    return float4(diffuse + specular + ambient, 1);
}

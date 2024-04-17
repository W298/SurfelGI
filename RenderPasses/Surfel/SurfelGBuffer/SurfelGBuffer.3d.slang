import RenderPasses.Surfel.SurfelUtils;

import Scene.Raster;

struct GBufferVSOut
{
    linear float3 normalW : NORMAL;
    linear float3 posW : POSW;
    nointerpolation GeometryInstanceID instanceID : INSTANCE_ID;
    float4 posH : SV_POSITION;
}

struct GBufferPSOut
{
    float4 normal : SV_TARGET0;
    uint4 packedHitInfo : SV_TARGET1;
    float4 instanceIDVisual : SV_TARGET2;
};

GBufferVSOut vsMain(VSIn vIn)
{
    GBufferVSOut vOut;
    const GeometryInstanceID instanceID = { vIn.instanceID };

    float4x4 worldMat = gScene.getWorldMatrix(instanceID);
    float3 posW = mul(worldMat, float4(vIn.pos, 1.f)).xyz;
    vOut.posW = posW;
    vOut.posH = mul(gScene.camera.getViewProj(), float4(posW, 1.f));

    vOut.instanceID = instanceID;
    vOut.normalW = mul(gScene.getInverseTransposeWorldMatrix(instanceID), vIn.unpack().normal);

    return vOut;
}

GBufferPSOut psMain(GBufferVSOut vOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
{
    TriangleHit triangleHit;
    triangleHit.instanceID = vOut.instanceID;
    triangleHit.primitiveIndex = triangleIndex;
    triangleHit.barycentrics = barycentrics.yz;

    GBufferPSOut psOut = {
        float4(vOut.normalW, 1),
        triangleHit.pack(),
        float4(pseudocolor(vOut.instanceID.index), 1)
    };

    return psOut;
}

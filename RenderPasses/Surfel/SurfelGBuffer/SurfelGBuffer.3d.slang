import RenderPasses.Surfel.HashUtils;

import Scene.Raster;

struct GBufferVSOut
{
    float2 texC : TEXCRD;
    nointerpolation GeometryInstanceID instanceID : INSTANCE_ID;
    nointerpolation uint materialID : MATERIAL_ID;
    float4 posH : SV_POSITION;
}

struct GBufferPSOut
{
    uint4 packedHitInfo : SV_TARGET0;
    float4 instanceIDVisual : SV_TARGET1;
};

GBufferVSOut vsMain(VSIn vsIn)
{
    GBufferVSOut vsOut;
    const GeometryInstanceID instanceID = { vsIn.instanceID };

    float4x4 worldMat = gScene.getWorldMatrix(instanceID);
    float3 posW = mul(worldMat, float4(vsIn.pos, 1.f)).xyz;
    vsOut.posH = mul(gScene.camera.getViewProj(), float4(posW, 1.f));

    vsOut.texC = vsIn.texC;
    vsOut.instanceID = instanceID;
    vsOut.materialID = gScene.getMaterialID(instanceID);

    return vsOut;
}

GBufferPSOut psMain(GBufferVSOut vsOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
{
    // Alpha test.
    VertexData v = {};
    v.texC = vsOut.texC;
    float lod = 0.f;

    if (gScene.materials.alphaTest(v, vsOut.materialID, lod))
        discard;

    // Store.
    TriangleHit triangleHit;
    triangleHit.instanceID = vsOut.instanceID;
    triangleHit.primitiveIndex = triangleIndex;
    triangleHit.barycentrics = barycentrics.yz;

    GBufferPSOut psOut = {
        triangleHit.pack(),
        float4(pseudocolor(vsOut.instanceID.index), 1)
    };

    return psOut;
}

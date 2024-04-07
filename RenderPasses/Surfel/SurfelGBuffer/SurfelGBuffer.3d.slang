#include "../SurfelUtils.hlsli"

import Scene.Raster;

struct GBufferPSOut
{
    float4 normal : SV_TARGET0;
    uint4 packedHitInfo : SV_TARGET1;
    float4 instanceIDVisual : SV_TARGET2;
};

VSOut vsMain(VSIn vIn)
{
    return defaultVS(vIn);
}

GBufferPSOut psMain(VSOut vOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
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

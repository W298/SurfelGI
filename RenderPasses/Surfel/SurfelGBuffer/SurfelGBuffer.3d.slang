#include "../Random.hlsli"

import Scene.Raster;

struct PSOut
{
    float4 normal : SV_TARGET0;
    uint instanceID : SV_TARGET1;
    float4 instanceIDVisual : SV_TARGET2;
};

VSOut vsMain(VSIn vIn)
{
    return defaultVS(vIn);
}

PSOut psMain(VSOut vOut, uint triangleIndex: SV_PrimitiveID)
{
    RandomState randomState = initRandomState(vOut.instanceID.index, 0);

    float3 faceNormal = gScene.getFaceNormalW(vOut.instanceID, triangleIndex);
    VertexData v = prepareVertexData(vOut, faceNormal);

    //GeometryInstanceID id = vOut.instanceID;
    //float4x4 transform = gScene->getWorldMatrix(id);

    PSOut psOut = {};

    psOut.normal = float4(v.normalW, 1);
    psOut.instanceID = vOut.instanceID.index;
    psOut.instanceIDVisual = float4(getNextFloat3(randomState), 1);    

    return psOut;
}

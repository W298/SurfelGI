#include "Utils/Math/MathConstants.slangh"

import Scene.Raytracing;
import RenderPasses.Surfel.HashUtils;

cbuffer CB
{
    uint2 gResolution;
}

struct Payload
{
    float3 origin;
    float3 direction;
    uint length;
};

RWTexture2D<uint4> gReflectionHitInfo;
RWTexture2D<float4> gReflectionDirection;
RWTexture2D<float4> gInstanceIDVisual;

[shader("miss")]
void miss(inout Payload payload)
{
    uint2 pixelPos = DispatchRaysIndex().xy;

    gReflectionHitInfo[pixelPos] = {};
    gReflectionDirection[pixelPos] = float4(-payload.direction, 0.f);
    gInstanceIDVisual[pixelPos] = float4(0.f);
}

[shader("anyhit")]
void anyHit(inout Payload payload, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

[shader("closesthit")]
void closeHit(inout Payload payload, BuiltInTriangleIntersectionAttributes attribs)
{
    uint2 pixelPos = DispatchRaysIndex().xy;

    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;

    VertexData v = gScene.getVertexData(triangleHit);

    if (payload.length >= 1)
    {
        gReflectionHitInfo[pixelPos] = triangleHit.pack();
        gReflectionDirection[pixelPos] = float4(-payload.direction, 0.f);
        gInstanceIDVisual[pixelPos] = float4(pseudocolor(triangleHit.instanceID.index), 1.f);
    }
    else
    {
        const float3 incidentRayDir = normalize(payload.direction);
        const float3 normal = normalize(v.normalW);
        const float3 reflectionRayDir = incidentRayDir - 2.f * dot(incidentRayDir, normal) * normal;

        payload.origin = v.posW;
        payload.direction = normalize(reflectionRayDir);
        payload.length++;

        RayDesc rayDesc;
        rayDesc.Origin = payload.origin;
        rayDesc.TMin = 0.f;
        rayDesc.TMax = FLT_MAX;
        rayDesc.Direction = payload.direction;

        TraceRay(
            gScene.rtAccel,
            RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
            0xff,
            0 /* hitIdx */,
            rayTypeCount,
            0 /* missIdx */,
            rayDesc,
            payload
        );
    }
}

[shader("raygeneration")]
void rayGen()
{
    uint2 pixelPos = DispatchRaysIndex().xy;

    // Trace ray
    const Ray ray = gScene.camera.computeRayPinhole(pixelPos, gResolution);

    Payload payload;
    payload.origin = ray.origin;
    payload.direction = ray.dir;
    payload.length = 0;

    TraceRay(
        gScene.rtAccel,
        RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        0xff,
        0 /* hitIdx */,
        rayTypeCount,
        0 /* missIdx */,
        ray.toRayDesc(),
        payload
    );
}

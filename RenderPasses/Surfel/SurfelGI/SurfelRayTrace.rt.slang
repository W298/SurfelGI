#define FLT_MAX 3.402823466e+38F

import Scene.Raytracing;
import Utils.Sampling.SampleGenerator;

import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtils;

cbuffer CB
{
    uint gFrameIndex;
}

struct Payload
{
    float3 radiance;
    bool terminated;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWStructuredBuffer<SurfelRay> gSurfelRayBuffer;

RWByteAddressBuffer gSurfelCounter;

// Miss Shaders

[shader("miss")]
void scatterMiss(inout Payload payload)
{
    payload.terminated = true;

    // TODO: Env light accumulation.
    float3 Le = gScene.envMap.eval(WorldRayDirection());
}

// Hit Shaders

[shader("anyhit")]
void scatterTriangleMeshAnyHit(inout Payload payload, BuiltInTriangleIntersectionAttributes attribs)
{
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout Payload payload, BuiltInTriangleIntersectionAttributes attribs)
{
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;

    VertexData v = gScene.getVertexData(triangleHit);
    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), 0.02f);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // TODO: For testing...
    for (uint i = 0; i < cellInfo.surfelCount; ++i)
    {
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        if (surfel.rayCount == 1)
            continue;

        float3 bias = v.posW - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < pow(surfel.radius, 2))
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(v.normalW, normal);
            if (dotN > 0)
                surfel.rayCount = 2;
        }

        gSurfelBuffer[surfelIndex] = surfel;
    }
}

// Ray Generation

[shader("raygeneration")]
void rayGen()
{
    uint totalRayCount = gSurfelCounter.Load((int)SurfelCounterOffset::RequestedRay);
    if (DispatchRaysIndex().x >= totalRayCount)
        return;

    uint rayIndex = DispatchRaysIndex().x;
    SurfelRay surfelRay = gSurfelRayBuffer[rayIndex];
    Surfel surfel = gSurfelBuffer[surfelRay.surfelIndex];

    RNG rng;
    rng.init(DispatchRaysIndex().xx, gFrameIndex);

    RayDesc ray;
    ray.Origin = surfel.position;
    ray.TMin = 0.0001;
    ray.TMax = FLT_MAX;
    ray.Direction = normalize(sample_hemisphere_cos(surfel.normal, rng));

    surfelRay.direction = ray.Direction;

    uint rayFlags = RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_CULL_BACK_FACING_TRIANGLES;

    Payload payload;
    TraceRay(
        gScene.rtAccel,
        rayFlags,
        0xff,
        0,  /* hitIdx */
        rayTypeCount,
        0,  /* missIdx */
        ray,
        payload
    );
}

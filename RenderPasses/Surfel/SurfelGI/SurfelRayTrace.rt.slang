import Scene.Raytracing;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;

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
    float3 thp;
    uint pathLength;
    float3 origin;
    float3 direction;
    bool terminated;

    SampleGenerator sg;

    __init(SampleGenerator sg)
    {
        this.radiance = float3(0, 0, 0);
        this.thp = float3(1, 1, 1);
        this.pathLength = 0;
        this.origin = float3(0, 0, 0);
        this.direction = float3(0, 0, 0);
        this.terminated = false;
    }
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWStructuredBuffer<SurfelRay> gSurfelRayBuffer;

RWByteAddressBuffer gSurfelCounter;

float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    RNG rng;
    rng.init(DispatchRaysIndex().xx, gFrameIndex);

    const uint lightIndex = rng.next_uint(lightCount - 1);
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

void handleHit(TriangleHit triangleHit, inout Payload payload)
{
    VertexData v = gScene.getVertexData(triangleHit);
    uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);
    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -payload.direction, lod);
    let mi = gScene.materials.getMaterialInstance(sd, lod);

    float3 Lr = evalAnalyticLight(sd, mi, payload.sg);

    payload.radiance += payload.thp * Lr;
    payload.terminated = true;

    // TODO: For testing ray generation...
    //int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), 0.02f);
    //if (!isCellValid(cellPos))
    //    return;

    //uint flattenIndex = getFlattenCellIndex(cellPos);
    //CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    //for (uint i = 0; i < cellInfo.surfelCount; ++i)
    //{
    //    uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
    //    Surfel surfel = gSurfelBuffer[surfelIndex];

    //    if (surfel.rayCount == 1)
    //        continue;

    //    float3 bias = v.posW - surfel.position;
    //    float dist2 = dot(bias, bias);

    //    if (dist2 < pow(surfel.radius, 2))
    //    {
    //        float3 normal = normalize(surfel.normal);

    //        float dotN = dot(v.normalW, normal);
    //        if (dotN > 0)
    //            surfel.rayCount = 2;
    //    }

    //    gSurfelBuffer[surfelIndex] = surfel;
    //}
}

// Miss Shaders

[shader("miss")]
void scatterMiss(inout Payload payload)
{
    // Env light accumulation.
    float3 Le = gScene.envMap.eval(-payload.direction);
    payload.radiance += payload.thp * Le;

    payload.terminated = true;
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
    handleHit(triangleHit, payload);
}

// Ray Generation

[shader("raygeneration")]
void rayGen()
{
    uint totalRayCount = gSurfelCounter.Load((int)SurfelCounterOffset::RequestedRay);
    if (DispatchRaysIndex().x >= totalRayCount)
        return;

    uint rayIndex = DispatchRaysIndex().x;
    uint2 rayIndex2 = uint2(rayIndex, rayIndex);
    SurfelRay surfelRay = gSurfelRayBuffer[rayIndex];
    const Surfel surfel = gSurfelBuffer[surfelRay.surfelIndex];

    RNG rng;
    rng.init(rayIndex2, gFrameIndex);

    RayDesc ray;
    ray.Origin = surfel.position;
    ray.TMin = 0.f;
    ray.TMax = kRayTMax;
    ray.Direction = normalize(sample_hemisphere_cos(surfel.normal, rng));

    SampleGenerator sg = SampleGenerator(rayIndex2, gFrameIndex);

    Payload payload = Payload(sg);
    payload.origin = ray.Origin;
    payload.direction = ray.Direction;

    // Direct Lighting
    {
        TriangleHit baseHit = TriangleHit(surfel.packedHitInfo);
        VertexData v = gScene.getVertexData(baseHit);
        uint materialID = gScene.getMaterialID(baseHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);
        const float3 direction = gScene.camera.getPosition() - surfel.position;
        ShadingData sd = gScene.materials.prepareShadingData(v, materialID, direction, lod);
        let mi = gScene.materials.getMaterialInstance(sd, lod);

        BSDFSample bsdfSample;
        if (mi.sample(sd, sg, bsdfSample, false))
            payload.thp *= bsdfSample.weight;

        float3 Lr = evalAnalyticLight(sd, mi, payload.sg);
        payload.radiance += payload.thp * Lr;
    }

    // In-Direct Lighting
    TraceRay(
        gScene.rtAccel,
        RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        0xff,
        0,  /* hitIdx */
        rayTypeCount,
        0,  /* missIdx */
        ray,
        payload
    );

    surfelRay.direction = ray.Direction;
    surfelRay.radiance = payload.radiance;

    gSurfelRayBuffer[rayIndex] = surfelRay;
}

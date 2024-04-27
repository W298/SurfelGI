import Scene.Raytracing;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;
import Utils.Geometry.GeometryHelpers;

import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

cbuffer CB
{
    uint gFrameIndex;
}

struct ScatterPayload
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

struct ShadowPayload
{
    bool visible;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWStructuredBuffer<SurfelRay> gSurfelRayBuffer;

RWByteAddressBuffer gSurfelCounter;

bool traceShadowRay(float3 origin, float3 dir, float distance)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = dir;
    ray.TMin = 0.f;
    ray.TMax = distance;

    ShadowPayload shadowPayload;
    shadowPayload.visible = false;
    TraceRay(
        gScene.rtAccel,
        RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
        0xff,
        1, /* hitIdx */
        rayTypeCount,
        1, /* missIdx */
        ray,
        shadowPayload
    );

    return shadowPayload.visible;
}

void traceScatterRay(inout ScatterPayload scatterPayload)
{
    RayDesc ray;
    ray.Origin = scatterPayload.origin;
    ray.TMin = 0.f;
    ray.TMax = kRayTMax;
    ray.Direction = scatterPayload.direction;

    TraceRay(
        gScene.rtAccel,
        RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        0xff,
        0, /* hitIdx */
        rayTypeCount,
        0, /* missIdx */
        ray,
        scatterPayload
    );
}

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

    const float3 origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
    bool V = traceShadowRay(origin, ls.dir, ls.distance);
    if (!V)
        return float3(0.f);

    return mi.eval(sd, ls.dir, sg) * ls.Li * invPdf;
}

void handleHit(TriangleHit triangleHit, inout ScatterPayload scatterPayload)
{
    VertexData v = gScene.getVertexData(triangleHit);
    uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);
    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -scatterPayload.direction, lod);
    let mi = gScene.materials.getMaterialInstance(sd, lod);

    float3 Lr = evalAnalyticLight(sd, mi, scatterPayload.sg);

    scatterPayload.radiance += scatterPayload.thp * Lr;
    scatterPayload.terminated = true;
}

// Miss Shaders

[shader("miss")]
void scatterMiss(inout ScatterPayload scatterPayload)
{
    // Env light accumulation.
    float3 Le = gScene.envMap.eval(-scatterPayload.direction);
    scatterPayload.radiance += scatterPayload.thp * Le;

    scatterPayload.terminated = true;
}

[shader("miss")]
void shadowMiss(inout ShadowPayload shadowPayload)
{
    shadowPayload.visible = true;
}

// Hit Shaders

[shader("anyhit")]
void scatterTriangleMeshAnyHit(inout ScatterPayload scatterPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout ScatterPayload scatterPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;
    handleHit(triangleHit, scatterPayload);
}

[shader("anyhit")]
void shadowTriangleMeshAnyHit(inout ShadowPayload shadowPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
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

    SampleGenerator sg = SampleGenerator(rayIndex2, gFrameIndex);

    ScatterPayload scatterPayload = ScatterPayload(sg);
    scatterPayload.origin = surfel.position;
    scatterPayload.direction = normalize(sample_hemisphere_cos(surfel.normal, rng));

    // Direct Lighting (for Debugging)
    {
        TriangleHit baseHit = TriangleHit(surfel.packedHitInfo);
        VertexData v = gScene.getVertexData(baseHit);
        uint materialID = gScene.getMaterialID(baseHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);
        const float3 direction = gScene.camera.getPosition() - surfel.position;
        ShadingData sd = gScene.materials.prepareShadingData(v, materialID, direction, lod);
        let mi = gScene.materials.getMaterialInstance(sd, lod);

        BSDFSample bsdfSample;
        if (mi.sample(sd, sg, bsdfSample, true))
            scatterPayload.thp *= bsdfSample.weight;

        float3 Lr = evalAnalyticLight(sd, mi, scatterPayload.sg);
        scatterPayload.radiance += scatterPayload.thp * Lr;
    }

    // In-Direct Lighting
    traceScatterRay(scatterPayload);

    surfelRay.radiance = scatterPayload.radiance;
    gSurfelRayBuffer[rayIndex] = surfelRay;
}

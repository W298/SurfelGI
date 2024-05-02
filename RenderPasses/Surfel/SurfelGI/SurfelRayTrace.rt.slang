#include "Utils/Math/MathConstants.slangh"

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
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

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
    ray.TMax = FLT_MAX;
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

// [Sample ONE light sources] and divide by pdf.
float3 evalAnalyticLight(const ShadingData sd, const IMaterialInstance mi, inout SampleGenerator sg)
{
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.f);

    RNG rng;
    rng.init(DispatchRaysIndex().xx, gFrameIndex);

    const uint lightIndex = rng.next_uint(lightCount - 1);
    float invPdf = lightCount;  // Probability is all same, so pdf is 1/N.

    AnalyticLightSample ls;
    if (!sampleLight(sd.posW, gScene.getLight(lightIndex), sg, ls))
        return float3(0.f);

    const uint lobeTypes = mi.getLobeTypes(sd);
    const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
    const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
    float NdotL = dot(sd.getOrientedFaceNormal(), ls.dir);
    if ((NdotL <= kMinCosTheta && !hasTransmission) || (NdotL >= -kMinCosTheta && !hasReflection))
        return float3(0.f);

    // Trace shadow ray to check light source is visible or not.
    const float3 origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
    if (!traceShadowRay(origin, ls.dir, ls.distance))
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

    // Calculate exitant radiance using light sources.
    // It do f(wi, wo) * dot(wo, n) * Li
    float3 Lr = evalAnalyticLight(sd, mi, scatterPayload.sg);
    scatterPayload.radiance += scatterPayload.thp * Lr;

    // Update path throughput using weight.
    // weight = f(wi, wo) * dot(wo, n) / pdf(wo)
    BSDFSample sample;
    if (mi.sample(sd, scatterPayload.sg, sample, true))
        scatterPayload.thp *= sample.weight;

    // Omit multiple bouncing by using radiance of surfel.
    // Access radiance of surfels to calculate exitant radiance.
    float4 nextLr = float4(0.f);
    {
        int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), 0.02f);
        if (!isCellValid(cellPos))
            return;

        uint flattenIndex = getFlattenCellIndex(cellPos);
        CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

        for (uint i = 0; i < cellInfo.surfelCount; ++i)
        {
            uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
            Surfel surfel = gSurfelBuffer[surfelIndex];

            float3 bias = v.posW - surfel.position;
            float dist2 = dot(bias, bias);

            if (dist2 < surfel.radius * surfel.radius)
            {
                float3 normal = normalize(surfel.normal);

                float dotN = dot(v.normalW, normal);
                if (dotN > 0)
                {
                    float dist = sqrt(dist2);
                    float contribution = 1.f;

                    contribution *= saturate(dotN);
                    contribution *= saturate(1 - dist / surfel.radius);
                    contribution = smoothstep(0, 1, contribution);

                    nextLr += float4(surfel.radiance, 1.f) * contribution;
                }
            }
        }
    }

    if (nextLr.w > 0)
        nextLr.xyz /= nextLr.w;

    scatterPayload.radiance += scatterPayload.thp * nextLr.xyz;
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
    SurfelRayResult surfelRayResult = gSurfelRayResultBuffer[rayIndex];
    const Surfel surfel = gSurfelBuffer[surfelRayResult.surfelIndex];

    RNG rng;
    rng.init(uint2(rayIndex, rayIndex), gFrameIndex);

    SampleGenerator sg = SampleGenerator(uint2(rayIndex, rayIndex), gFrameIndex);

    ScatterPayload scatterPayload = ScatterPayload(sg);
    scatterPayload.origin = surfel.position;
    scatterPayload.direction = normalize(sample_hemisphere_cos(surfel.normal, rng));

    // Store first direction.
    surfelRayResult.direction = scatterPayload.direction;

    // Trace ray.
    traceScatterRay(scatterPayload);

    // Store final radiance.
    surfelRayResult.radiance = scatterPayload.radiance;

    // Write back to buffer.
    gSurfelRayResultBuffer[rayIndex] = surfelRayResult;
}

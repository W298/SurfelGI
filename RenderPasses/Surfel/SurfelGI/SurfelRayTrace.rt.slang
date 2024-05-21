#include "Utils/Math/MathConstants.slangh"

import Scene.Raytracing;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;
import Utils.Geometry.GeometryHelpers;
import Utils.Color.ColorHelpers;
import Utils.Math.MathHelpers;
import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

/**
    Raytracing shader for surfel GI.
    
    First, ray steps until the RayStep value is reached.
    At last step (= RayStep), try to finalize path using surfel radiance.
    It is possible to skip forward bounces by using surfel radiance.
        But if surfel radiance is invalid, goto next step, even if it is last step.
        By doing this, it is possible to trace areas where surfel does not exist.
            But if ray exceed MaxStep, terminate path, no matter what.
            Because it is possible to stuck in infinite loop.
*/

cbuffer CB
{
    uint gFrameIndex;                   ///< Frame index.
    uint gRayStep;                      ///< How many steps does ray go.
    uint gMaxStep;                      ///< Global maxium step count. No ray step can exceed this value.
    bool gUseSurfelRadiance;            ///< Use surfel radiance or not.
    uint gMaxSurfelForStep;
    bool gUseRayGuiding;
}

struct ScatterPayload
{
    float3 radiance;
    float3 thp;
    float3 origin;
    float3 direction;
    uint currStep;
    bool terminated;

    SampleGenerator sg;

    __init(SampleGenerator sg)
    {
        this.radiance = float3(0, 0, 0);
        this.thp = float3(1, 1, 1);
        this.origin = float3(0, 0, 0);
        this.direction = float3(0, 0, 0);
        this.currStep = 1;                  // Be aware. Start from 1.
        this.terminated = false;            // if true, path will be terminated.
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
ByteAddressBuffer gSurfelConfig;

RWTexture2D<float> gIrradianceMap;

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

// Omit multiple bouncing by using radiance of surfel.
// Return true if surfel radiance is valid, and successfully applied.
// Return false if surfel is invalid, so need to goto next step.
bool finalize(inout ScatterPayload scatterPayload, const VertexData v)
{
    if (!gUseSurfelRadiance)
    {
        return true;
    }

    float4 Lr = float4(0.f);
    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), config.cellUnit);
    if (!isCellValid(cellPos))
    {
        // Surfel radiance is invalid.
        // Need to goto next step, so, do not terminate path.
        return false;
    }

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    for (uint i = 0; i < gMaxSurfelForStep; ++i)
    {
        uint randomSelection = sampleNext1D(scatterPayload.sg) * (cellInfo.surfelCount - 1);
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + randomSelection];
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

                Lr += float4(surfel.radiance, 1.f) * contribution;
            }
        }
    }

    if (Lr.w <= 0.f)
    {
        // No surfel found.
        // Need to goto next step, so, do not terminate path.
        return false;
    }

    // Surfel radiance is valid, so use it.
    Lr.xyz /= Lr.w;
    scatterPayload.radiance += scatterPayload.thp * Lr.xyz;

    return true;
}

void handleHit(TriangleHit triangleHit, inout ScatterPayload scatterPayload)
{
    VertexData v = gScene.getVertexData(triangleHit);
    uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);
    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -scatterPayload.direction, lod);
    let mi = gScene.materials.getMaterialInstance(sd, lod);

    // Only use diffuse lobe.
    sd.mtl.setActiveLobes((uint)LobeType::Diffuse);

    // Calculate exitant radiance using light sources.
    // It do f(wi, wo) * dot(wo, n) * Li
    float3 Lr = evalAnalyticLight(sd, mi, scatterPayload.sg);
    scatterPayload.radiance += scatterPayload.thp * Lr;

    // Prepare next ray.
    // If failed to sample, terminate path.
    BSDFSample sample;
    if (mi.sample(sd, scatterPayload.sg, sample, true))
    {
        scatterPayload.origin = sd.computeRayOrigin();
        scatterPayload.direction = sample.wo;
        scatterPayload.thp *= sample.weight;
    }
    else
    {
        scatterPayload.terminated = true;
        return;
    }

    // Finialize path if path length reached to last step.
    if (scatterPayload.currStep < gRayStep)
    {
        // Russian roulette.
        const float rrValue = luminance(scatterPayload.thp);
        const float prob = max(0.f, 1.f - rrValue);

        if (sampleNext1D(scatterPayload.sg) >= prob)
        {
            scatterPayload.thp /= max(1e-12f, 1.f - prob);

            // Check throughput is valid.
            // If valid, goto next step, or terminate path.
            bool thpValid = any(scatterPayload.thp > 0.f);
            if (thpValid)
                scatterPayload.currStep++;
            else
                scatterPayload.terminated = true;

            return;
        }
    }
    
    // If path length reached to last step,
    // or russian roulette failed, try to finalize path.
    // If failed to finalize, goto next step.
    if (finalize(scatterPayload, v))
        scatterPayload.terminated = true;
    else
        scatterPayload.currStep++;
}

// Miss Shaders

[shader("miss")]
void scatterMiss(inout ScatterPayload scatterPayload)
{
    // Evaluate environment map.
    float3 Le = gScene.envMap.eval(-scatterPayload.direction);
    scatterPayload.radiance += scatterPayload.thp * Le;
    scatterPayload.terminated = true;
}

[shader("miss")]
void shadowMiss(inout ShadowPayload shadowPayload)
{
    // If shadow ray miss, it means light is visible.
    shadowPayload.visible = true;
}

// Hit Shaders

[shader("anyhit")]
void scatterAnyHit(inout ScatterPayload scatterPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

[shader("closesthit")]
void scatterCloseHit(inout ScatterPayload scatterPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;

    handleHit(triangleHit, scatterPayload);
}

[shader("anyhit")]
void shadowAnyhit(inout ShadowPayload shadowPayload, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test.
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
    const uint surfelIndex = surfelRayResult.surfelIndex;
    const Surfel surfel = gSurfelBuffer[surfelIndex];

    RNG rng;
    rng.init(uint2(rayIndex, rayIndex), gFrameIndex);

    SampleGenerator sg = SampleGenerator(uint2(rayIndex, rayIndex) + uint2(gFrameIndex), gFrameIndex);

    // Initialize scatter payload.
    ScatterPayload scatterPayload = ScatterPayload(sg);
    scatterPayload.origin = surfel.position;

    float3 dirLocal;
    float pdf;

    uint2 irrMapBase = uint2(
        surfelIndex % (kIrradianceMapRes.x / kIrradianceMapUnit.x),
        surfelIndex / (kIrradianceMapRes.x / kIrradianceMapUnit.y)
    );
    irrMapBase *= kIrradianceMapUnit;

    // If hole dosen't exist, and ray count of surfel is bigger than 16, apply ray-guiding.
    if (gUseRayGuiding && !surfel.hasHole && step(16u, surfel.rayCount))
    {
        // Approximate inverse CDF for sampling.
        float randomCeil = rng.next_float() * surfel.sumLuminance;
        float cummulative = 0.f;

        int2 coord;
        for (uint y = 0; y < kIrradianceMapUnit.y; ++y)
        {
            for (uint x = 0; x < kIrradianceMapUnit.x; ++x)
            {
                cummulative += gIrradianceMap[irrMapBase + uint2(x, y)];
                if (cummulative >= randomCeil)
                {
                    coord = int2(x, y);
                    pdf = gIrradianceMap[irrMapBase + uint2(x, y)] / surfel.sumLuminance;
                    break;
                }
            }

            if (cummulative >= randomCeil)
                break;
        }

        float2 uv = float2(coord - kIrradianceMapHalfUnit) / float2(kIrradianceMapHalfUnit);
        dirLocal = octDecode(uv);

        // Add small noise to direction.
        float3 noise = normalize(hemispherepoint_uniform(rng.next_float(), rng.next_float()));
        dirLocal = normalize(dirLocal + 0.1f * noise);
    }
    else
    {
        dirLocal = normalize(hemispherepoint_uniform(rng.next_float(), rng.next_float()));
        pdf = 1.f / (16 * M_PI);
    }

    float3 dirWorld = normalize(mul(dirLocal, get_tangentspace(surfel.normal)));

    scatterPayload.direction = dirWorld;

    // Store direction and pdf to result first, because payload direction will be changed.
    surfelRayResult.dirLocal = dirLocal;
    surfelRayResult.dirWorld = dirWorld;
    surfelRayResult.pdf = pdf;

    // Trace ray.
    while (!scatterPayload.terminated && scatterPayload.currStep <= gMaxStep)
        traceScatterRay(scatterPayload);

    // Store final radiance to result.
    surfelRayResult.radiance = scatterPayload.radiance;

    // Write back to buffer.
    gSurfelRayResultBuffer[rayIndex] = surfelRayResult;
}

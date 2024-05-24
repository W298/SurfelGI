import Scene.Scene;
import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.HashUtils;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

cbuffer CB
{
    uint gFrameIndex;
    uint gBlendingDelay;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRecycleInfo> gSurfelRecycleInfoBuffer;

ByteAddressBuffer gSurfelConfig;

Texture2D<uint4> gPackedHitInfo;
RWTexture2D<float4> gOutput;

[numthreads(16, 16, 1)]
void csMain(
    uint3 dispatchThreadId: SV_DispatchThreadID,
    uint groupIndex: SV_GroupIndex,
    uint3 groupThreadID: SV_GroupThreadID,
    uint3 groupdId: SV_GroupID
)
{
    uint2 pixelPos = dispatchThreadId.xy;

    RNG randomState;
    randomState.init(pixelPos, gFrameIndex);

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
        return;

    TriangleHit triangleHit = hitInfo.getTriangleHit();
    VertexData v = gScene.getVertexData(triangleHit);
    float4 curPosH = mul(gScene.camera.data.viewProjMatNoJitter, float4(v.posW, 1.f));
    float depth = curPosH.z / curPosH.w;

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    float4 indirectLighting = float4(0.f);
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

                const SurfelRecycleInfo surfelRecycleInfo = gSurfelRecycleInfoBuffer[surfelIndex];

                // Delay blending if not sufficient sample is accumulated.
                // Because samples are updated per frame, so do not use sample count directly.
                indirectLighting += float4(surfel.radiance, 1.f) * contribution * smoothstep(0, gBlendingDelay, surfelRecycleInfo.frame);
            }
        }
    }

    if (indirectLighting.w > 0)
    {
        indirectLighting.xyz /= indirectLighting.w;
        indirectLighting.w = saturate(indirectLighting.w);
    }

    gOutput[pixelPos] = indirectLighting;
}

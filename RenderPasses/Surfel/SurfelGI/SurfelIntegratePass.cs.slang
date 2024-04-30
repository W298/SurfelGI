import Scene.Scene;

import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

cbuffer CB
{
    uint2 gResolution;
    float gSurfelVisualRadius;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

ByteAddressBuffer gSurfelConfig;

Texture2D<uint4> gPackedHitInfo;

[numthreads(32, 32, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID, uint3 groupdId: SV_GroupID)
{
    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 pixelPos = dispatchThreadId.xy;
    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
        return;

    VertexData v = gScene.getVertexData(hitInfo.getTriangleHit());

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // Moving average radiance
    for (uint i = 0; i < cellInfo.surfelCount; ++i)
    {
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
        {
            float3 rayRadiance = gSurfelRayResultBuffer[surfel.rayOffset + rayIndex].radiance;
            float weight = 1.0f / ++surfel.accumulated;

            surfel.radiance = lerp(surfel.radiance, rayRadiance, weight);
        }

        // Write back to buffer
        gSurfelBuffer[surfelIndex] = surfel;
    }
}

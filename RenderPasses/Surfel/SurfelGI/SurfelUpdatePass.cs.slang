import Scene.Scene;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

cbuffer CB
{
    float3 gCameraPos;
    uint2 gResolution;
    float gFOVy;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
StructuredBuffer<uint> gSurfelDirtyIndexBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<uint> gSurfelFreeIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;

RWByteAddressBuffer gSurfelCounter;
ByteAddressBuffer gSurfelConfig;

// Calculate how much surfels are located at cell.
[numthreads(32, 1, 1)]
void collectCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint dirtySurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::DirtySurfel);
    if (dispatchThreadId.x >= dirtySurfelCount)
        return;

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    uint surfelIndex = gSurfelDirtyIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    float surfelRadius = surfel.radius;
    if (surfelRadius > 0)
    {
        // Copy surfel index if radius is not zero.
        uint validSurfelCount;
        gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::ValidSurfel, 1, validSurfelCount);
        gSurfelValidIndexBuffer[validSurfelCount] = surfelIndex;

        // Update surfel position, normal, radius.
        TriangleHit hit = TriangleHit(surfel.packedHitInfo);
        VertexData data = gScene.getVertexData(hit);

        surfel.position = data.posW;
        surfel.normal = data.normalW;
        surfel.radius = calcSurfelRadius(
            distance(gScene.camera.getPosition(), surfel.position),
            gFOVy,
            gResolution,
            config.surfelTargetArea,
            config.cellUnit
        );

        // Calculate number of surfels located at cell.
        int3 cellPos = getCellPos(surfel.position, gCameraPos, config.cellUnit);
        for (uint i = 0; i < 27; ++i)
        {
            int3 neighborPos = cellPos + neighborOffset[i];
            if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos, config.cellUnit))
            {
                uint flattenIndex = getFlattenCellIndex(neighborPos);
                InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1);
            }
        }

        // Ray allocation.
        uint rayOffset = 0;
        uint rayRequestCount = 32;
        gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::RequestedRay, rayRequestCount, rayOffset);

        if (rayOffset < kRayBudget)
        {
            surfel.rayOffset = rayOffset;
            surfel.rayCount = rayRequestCount;

            SurfelRayResult initSurfelRayResult;
            initSurfelRayResult.surfelIndex = surfelIndex;

            for (uint rayIndex = 0; rayIndex < rayRequestCount; ++rayIndex)
                gSurfelRayResultBuffer[rayOffset + rayIndex] = initSurfelRayResult;
        }

        // Write back to buffer.
        gSurfelBuffer[surfelIndex] = surfel;
    }
    else
    {
        int freeSurfelCount;
        gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::FreeSurfel, 1, freeSurfelCount);
        gSurfelFreeIndexBuffer[freeSurfelCount] = surfelIndex;
    }
}

// Calculate offset of cell to surfel buffer.
[numthreads(64, 1, 1)]
void accumulateCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    if (dispatchThreadId.x >= kCellCount)
        return;

    uint flattenIndex = dispatchThreadId.x;
    if (gCellInfoBuffer[flattenIndex].surfelCount == 0)
        return;

    // Calculate offsets.
    gSurfelCounter.InterlockedAdd(
        (int)SurfelCounterOffset::Cell,
        gCellInfoBuffer[flattenIndex].surfelCount,
        gCellInfoBuffer[flattenIndex].cellToSurfelBufferOffset
    );

    gCellInfoBuffer[flattenIndex].surfelCount = 0;
}

// Update cell to surfel buffer using pre-calculated offsets.
// This operation is duplicated, might be possible to merge.
[numthreads(32, 1, 1)]
void updateCellToSurfelBuffer(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint vaildSurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::ValidSurfel);
    if (dispatchThreadId.x >= vaildSurfelCount)
        return;

    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    int3 cellPos = getCellPos(surfel.position, gCameraPos, config.cellUnit);
    for (uint i = 0; i < 27; ++i)
    {
        int3 neighborPos = cellPos + neighborOffset[i];
        if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos, config.cellUnit))
        {
            uint flattenIndex = getFlattenCellIndex(neighborPos);

            uint prevCount;
            InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1, prevCount);

            gCellToSurfelBuffer[gCellInfoBuffer[flattenIndex].cellToSurfelBufferOffset + prevCount] = surfelIndex;
        }
    }
}

#include "../SurfelTypes.hlsli"
#include "../SurfelUtils.hlsli"

import Scene.Scene;

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

RWByteAddressBuffer gSurfelCounter;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

// Calculate how much surfels are located at cell.
[numthreads(32, 1, 1)]
void collectCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint dirtySurfelCount = gSurfelCounter.Load(SURFEL_COUNTER_DIRTY_SURFEL);
    if (dispatchThreadId.x >= dirtySurfelCount)
        return;

    uint surfelIndex = gSurfelDirtyIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    float surfelRadius = surfel.radius;
    if (surfelRadius > 0)
    {
        // Copy surfel index if radius is not zero.
        uint validSurfelCount;
        gSurfelCounter.InterlockedAdd(SURFEL_COUNTER_VALID_SURFEL, 1, validSurfelCount);
        gSurfelValidIndexBuffer[validSurfelCount] = surfelIndex;

        // Update surfel position and normal.
        TriangleHit hit = TriangleHit(surfel.packedHitInfo);
        VertexData data = gScene.getVertexData(hit);

        surfel.position = data.posW;
        surfel.normal = data.normalW;

        surfel.radius = calcSurfelRadius(
            distance(gScene.camera.getPosition(), surfel.position),
            gFOVy,
            gResolution
        );

        // Calculate number of surfels located at cell.
        int3 cellPos = getCellPos(surfel.position, gCameraPos);
        for (uint i = 0; i < 27; ++i)
        {
            int3 neighborPos = cellPos + neighborOffset[i];
            if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos))
            {
                uint flattenIndex = getFlattenCellIndex(neighborPos);
                InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1);
            }
        }

        // Write back to buffer.
        gSurfelBuffer[surfelIndex] = surfel;
    }
    else
    {
        int freeSurfelCount;
        gSurfelCounter.InterlockedAdd(SURFEL_COUNTER_FREE_SURFEL, 1, freeSurfelCount);
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
        SURFEL_COUNTER_CELL,
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
    uint vaildSurfelCount = gSurfelCounter.Load(SURFEL_COUNTER_VALID_SURFEL);
    if (dispatchThreadId.x >= vaildSurfelCount)
        return;

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    int3 cellPos = getCellPos(surfel.position, gCameraPos);
    for (uint i = 0; i < 27; ++i)
    {
        int3 neighborPos = cellPos + neighborOffset[i];
        if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos))
        {
            uint flattenIndex = getFlattenCellIndex(neighborPos);

            uint prevCount;
            InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1, prevCount);

            gCellToSurfelBuffer[gCellInfoBuffer[flattenIndex].cellToSurfelBufferOffset + prevCount] = surfelIndex;
        }
    }
}

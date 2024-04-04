import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

cbuffer CB
{
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint32_t> gCellToSurfelBuffer;

[numthreads(32, 1, 1)]
void collectCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint totalSurfelCount = gSurfelStatus.Load<uint32_t>((uint)SurfelStatusOffset::TotalSurfelCount);
    if (dispatchThreadId.x >= totalSurfelCount)
        return;

    uint surfelIndex = dispatchThreadId.x;
    Surfel surfel = gSurfelBuffer[surfelIndex];

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
}

[numthreads(64, 1, 1)]
void accumulateCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    if (dispatchThreadId.x >= kCellCount)
        return;

    uint flattenIndex = dispatchThreadId.x;
    if (gCellInfoBuffer[flattenIndex].surfelCount == 0)
        return;

    gSurfelStatus.InterlockedAdd(
        (uint)SurfelStatusOffset::CellCount,
        gCellInfoBuffer[flattenIndex].surfelCount,
        gCellInfoBuffer[flattenIndex].cellToSurfelBufferOffset
    );

    gCellInfoBuffer[flattenIndex].surfelCount = 0;
}

[numthreads(32, 1, 1)]
void updateCellToSurfelBuffer(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint totalSurfelCount = gSurfelStatus.Load<uint32_t>((uint)SurfelStatusOffset::TotalSurfelCount);
    if (dispatchThreadId.x >= totalSurfelCount)
        return;

    uint surfelIndex = dispatchThreadId.x;
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

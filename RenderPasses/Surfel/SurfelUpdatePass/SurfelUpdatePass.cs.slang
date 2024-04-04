import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

cbuffer CB
{
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint32_t> gCellIndexBuffer;

[numthreads(32, 1, 1)]
void collectCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint surfelCount = gSurfelStatus.Load<uint32_t>((uint)SurfelStatusOffset::SurfelCount);
    if (dispatchThreadId.x >= surfelCount)
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
            InterlockedAdd(gCellInfoBuffer[flattenIndex].count, 1);
        }
    }
}

[numthreads(64, 1, 1)]
void accumulateCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    if (dispatchThreadId.x >= kCellCount)
        return;

    uint flattenIndex = dispatchThreadId.x;
    if (gCellInfoBuffer[flattenIndex].count == 0)
        return;

    gSurfelStatus.InterlockedAdd(
        (uint)SurfelStatusOffset::CellCount,
        gCellInfoBuffer[flattenIndex].count,
        gCellInfoBuffer[flattenIndex].offset
    );

    gCellInfoBuffer[flattenIndex].count = 0;
}

[numthreads(32, 1, 1)]
void updateCellIB(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint surfelCount = gSurfelStatus.Load<uint32_t>((uint)SurfelStatusOffset::SurfelCount);
    if (dispatchThreadId.x >= surfelCount)
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
            InterlockedAdd(gCellInfoBuffer[flattenIndex].count, 1, prevCount);

            gCellIndexBuffer[gCellInfoBuffer[flattenIndex].offset + prevCount] = surfelIndex;
        }
    }
}

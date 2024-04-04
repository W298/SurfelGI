import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.SurfelUtil;

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint32_t> gCellToSurfelBuffer;

[numthreads(1, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    // #TODO

    gSurfelStatus.Store((uint)SurfelStatusOffset::CellCount, 0);
}

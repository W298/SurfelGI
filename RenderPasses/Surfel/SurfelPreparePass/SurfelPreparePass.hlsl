#include "../SurfelTypes.hlsli"

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelCounter;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

[numthreads(1, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    gSurfelCounter.Store(SURFEL_COUNTER_VALID_SURFEL, clamp(gSurfelCounter.Load(SURFEL_COUNTER_VALID_SURFEL), 0, kTotalSurfelLimit));
    gSurfelCounter.Store(SURFEL_COUNTER_FREE_SURFEL, clamp(asint(gSurfelCounter.Load(SURFEL_COUNTER_FREE_SURFEL)), 0, (int)kTotalSurfelLimit));
    gSurfelCounter.Store(SURFEL_COUNTER_CELL, 0);
}

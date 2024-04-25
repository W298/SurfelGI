import RenderPasses.Surfel.SurfelTypes;

RWByteAddressBuffer gSurfelCounter;

[numthreads(1, 1, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const uint dirtySurfelCount = clamp(gSurfelCounter.Load((int)SurfelCounterOffset::ValidSurfel), 0, kTotalSurfelLimit);

    gSurfelCounter.Store((int)SurfelCounterOffset::ValidSurfel, 0);
    gSurfelCounter.Store((int)SurfelCounterOffset::DirtySurfel, dirtySurfelCount);
    gSurfelCounter.Store( (int)SurfelCounterOffset::FreeSurfel, clamp(asint(gSurfelCounter.Load((int)SurfelCounterOffset::FreeSurfel)), 0, (int)kTotalSurfelLimit));
    gSurfelCounter.Store((int)SurfelCounterOffset::Cell, 0);

    // TODO: For testing...
    //gSurfelCounter.Store((int)SurfelCounterOffset::RequestedRay, 0);
}

import Scene.Scene;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;
import RenderPasses.Surfel.SurfelGI.StaticParams;

cbuffer CB
{
    float3 gCameraPos;
    uint2 gResolution;
    float gFOVy;
    bool gLockSurfel;
    float gVarianceSensitivity;
    uint gMinRayCount;
    uint gMaxRayCount;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<uint4> gSurfelGeometryBuffer;
StructuredBuffer<uint> gSurfelDirtyIndexBuffer;
RWStructuredBuffer<uint> gSurfelValidIndexBuffer;
RWStructuredBuffer<uint> gSurfelFreeIndexBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;
RWStructuredBuffer<SurfelRayResult> gSurfelRayResultBuffer;
RWStructuredBuffer<SurfelRecycleInfo> gSurfelRecycleInfoBuffer;

RWByteAddressBuffer gSurfelReservationBuffer;
RWByteAddressBuffer gSurfelRefCounter;
RWByteAddressBuffer gSurfelCounter;

// Calculate how much surfels are located at cell.
[numthreads(32, 1, 1)]
void collectCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint dirtySurfelCount = gSurfelCounter.Load((int)SurfelCounterOffset::DirtySurfel);
    if (dispatchThreadId.x >= dirtySurfelCount)
        return;

    uint surfelIndex = gSurfelDirtyIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    float surfelRadius = surfel.radius;
    SurfelRecycleInfo surfelRecycleInfo = gSurfelRecycleInfoBuffer[surfelIndex];
    bool isSleeping = surfelRecycleInfo.status & 0x0001;
    bool lastSeen = surfelRecycleInfo.status & 0x0002;

    // Increase frame count and reduce life.
    surfelRecycleInfo.life = max(asint(surfelRecycleInfo.life) - 1, 0);
    surfelRecycleInfo.frame = clamp(asint(surfelRecycleInfo.frame) + 1, 0, 65535);

    // Check surfel is seen at last frame.
    // If so, reset life.
    // If so, and surfel is sleeping, awake.
    if (lastSeen)
    {
        surfelRecycleInfo.life = kMaxLife;
        if (isSleeping)
            isSleeping = false;
    }

    const bool hasEnoughRefCount = gSurfelRefCounter.Load(surfelIndex) > kRefCountThreshold;

    // Check sleeping surfel is still vaild or not.
    // If valid, reset life.
    if (isSleeping && hasEnoughRefCount)
        surfelRecycleInfo.life = kSleepingMaxLife;

    // Radius of surfel <= 0 means that the surfel should be destroyed.
    // Filter invalid surfels by checking radius and life.
    if (surfelRadius > 0 && surfelRecycleInfo.life > 0)
    {
        // Copy surfel index.
        uint validSurfelCount;
        gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::ValidSurfel, 1, validSurfelCount);
        gSurfelValidIndexBuffer[validSurfelCount] = surfelIndex;

        // Get vertex data using geometry info.
        TriangleHit hit = TriangleHit(gSurfelGeometryBuffer[surfelIndex]);
        VertexData data = gScene.getVertexData(hit);

        if (!gLockSurfel)
        {
            // Update surfel position, normal.
            surfel.position = data.posW;
            surfel.normal = data.normalW;

            // If surfel is sleeping, increase target area.
            surfel.radius = calcSurfelRadius(
                distance(gScene.camera.getPosition(), surfel.position),
                gFOVy,
                gResolution,
                kSurfelTargetArea * (isSleeping ? 16.f : 1.f),
                kCellUnit
            );

            // Limit lower bound of surfel radius when sleeping.
            if (isSleeping)
                surfel.radius = max(surfel.radius, kCellUnit * 0.5f);
        }

        // Calculate number of surfels located at cell.
        int3 cellPos = getCellPos(surfel.position, gCameraPos, kCellUnit);
        for (uint i = 0; i < 125; ++i)
        {
            int3 neighborPos = cellPos + neighborOffset[i];
            if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos, kCellUnit))
            {
                uint flattenIndex = getFlattenCellIndex(neighborPos);
                InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1);
            }
        }

        if (!gLockSurfel)
        {
            // Ray allocation by using MSME variance.
            // If surfel is sleeping surfel, reduce ray count.
            uint lower = isSleeping ? (gMinRayCount / 4u) : (gMaxRayCount / 4u);
            uint upper = isSleeping ? gMinRayCount : gMaxRayCount;

            uint rayOffset = 0;
            uint rayRequestCount = clamp(lerp(lower, upper, length(surfel.msmeData.variance) * gVarianceSensitivity), lower, upper);
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

            // Set status value. Last seen value is always reset.
            surfelRecycleInfo.status = isSleeping ? 0x0001 : 0x0000;

            // Write back to buffer.
            gSurfelRecycleInfoBuffer[surfelIndex] = surfelRecycleInfo;
            gSurfelBuffer[surfelIndex] = surfel;

            // Reset surfel ref count.
            gSurfelRefCounter.Store(surfelIndex, 0);
        }
    }
    else
    {
        if (!gLockSurfel)
        {
            // De-allocate surfel.
            int freeSurfelCount;
            gSurfelCounter.InterlockedAdd((int)SurfelCounterOffset::FreeSurfel, 1, freeSurfelCount);
            gSurfelFreeIndexBuffer[freeSurfelCount] = surfelIndex;
        }
    }
}

// Calculate offset of cell to surfel buffer.
[numthreads(64, 1, 1)]
void accumulateCellInfo(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    if (dispatchThreadId.x >= kCellCount)
        return;

    uint flattenIndex = dispatchThreadId.x;
    gSurfelReservationBuffer.Store(flattenIndex, 0u);

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

    uint surfelIndex = gSurfelValidIndexBuffer[dispatchThreadId.x];
    Surfel surfel = gSurfelBuffer[surfelIndex];

    // Check surfel is intersected with neighbor cells.
    int3 cellPos = getCellPos(surfel.position, gCameraPos, kCellUnit);
    for (uint i = 0; i < 125; ++i)
    {
        int3 neighborPos = cellPos + neighborOffset[i];
        if (isSurfelIntersectCell(surfel, neighborPos, gCameraPos, kCellUnit))
        {
            uint flattenIndex = getFlattenCellIndex(neighborPos);

            uint prevCount;
            InterlockedAdd(gCellInfoBuffer[flattenIndex].surfelCount, 1, prevCount);

            gCellToSurfelBuffer[gCellInfoBuffer[flattenIndex].cellToSurfelBufferOffset + prevCount] = surfelIndex;
        }
    }
}

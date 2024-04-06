#include "../Random.hlsli"
#include "../SurfelTypes.hlsli"
#include "../SurfelUtils.hlsli"

cbuffer CB
{
    float2 gInvResolution;
    float4x4 gInvViewProj;
    uint gFrameIndex;
    float3 gCameraPos;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWByteAddressBuffer gSurfelStatus;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

Texture2D<float> gDepth;
Texture2D<float4> gNormal;
Texture2D<uint> gCoverage;

RWTexture2D<float4> gOutput;

[numthreads(16, 16, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID)
{
    uint2 tilePos = dispatchThreadId.xy / kTileSize;
    uint2 pixelPos = dispatchThreadId.xy;

    float depth = gDepth[pixelPos];
    if (depth == 1)
        return;

    uint coverageData = gCoverage[tilePos];
    float coverage = f16tof32((coverageData & 0xFFFF0000) >> 16);
    uint x = (coverageData & 0x000000F0) >> 4;
    uint y = (coverageData & 0x0000000F) >> 0;

    float3 worldPos = unProject(pixelPos * gInvResolution, depth, gInvViewProj);

    int3 cellPos = getCellPos(worldPos, gCameraPos);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    if (cellInfo.surfelCount < kPerCellSurfelLimit)
    {
        if (groupThreadID.x == x && groupThreadID.y == y && coverage < kCoverageThreshold)
        {
            const float chance = pow(depth, 8);
            RandomState randomState = initRandomState(pixelPos, gFrameIndex);

            if (getNextFloat(randomState) < chance)
            {
                uint aliveCount;
                gSurfelStatus.InterlockedAdd(kSurfelStatus_TotalSurfelCount, 1, aliveCount);

                if (aliveCount < kTotalSurfelLimit)
                {
                    float3 normal = gNormal[pixelPos].xyz;
                    float3 randomColor = getNextFloat3(randomState);

                    Surfel newSurfel = { worldPos, normal, randomColor };
                    gSurfelBuffer[aliveCount] = newSurfel;
                }
                else
                {
                    // #TODO
                    gSurfelStatus.InterlockedAdd(kSurfelStatus_TotalSurfelCount, -1, aliveCount);
                }
            }
        }
    }

    // Visualize
    float3 blendedColor = float3(0, 0, 0);
    uint blendedCount = 0;

    for (uint i = 0; i < cellInfo.surfelCount; ++i)
    {
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        float3 bias = worldPos - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < kSurfelRadius * kSurfelRadius)
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(gNormal[pixelPos].xyz, normal);
            if (dotN > 0)
            {
                blendedColor += surfel.color;
                blendedCount++;
            }
        }
    }

    blendedColor /= max(1, blendedCount);
    blendedColor *= 0.8f;

    gOutput[pixelPos] = float4(blendedColor, 1);
}

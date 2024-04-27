import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.SurfelUtils;

import Scene.Scene;

cbuffer CB
{
    uint2 gResolution;
    float gSurfelVisualRadius;
}

RWStructuredBuffer<Surfel> gSurfelBuffer;
RWStructuredBuffer<CellInfo> gCellInfoBuffer;
RWStructuredBuffer<uint> gCellToSurfelBuffer;

RWStructuredBuffer<SurfelRay> gSurfelRayBuffer;

ByteAddressBuffer gSurfelConfig;

Texture2D<uint4> gPackedHitInfo;

RWTexture2D<float4> gOutput;

[numthreads(32, 32, 1)]
void csMain(uint3 dispatchThreadId: SV_DispatchThreadID, uint3 groupThreadID: SV_GroupThreadID, uint3 groupdId: SV_GroupID)
{
    if (dispatchThreadId.x >= gResolution.x || dispatchThreadId.y >= gResolution.y)
        return;

    uint2 pixelPos = dispatchThreadId.xy;
    SurfelConfig config = gSurfelConfig.Load<SurfelConfig>(0);

    HitInfo hitInfo = HitInfo(gPackedHitInfo[pixelPos]);
    if (!hitInfo.isValid())
    {
        const float3 direction = gScene.camera.computeRayPinhole(pixelPos, gResolution).dir;
        gOutput[pixelPos] = float4(gScene.envMap.eval(direction), 1);
        return;
    }

    VertexData v = gScene.getVertexData(hitInfo.getTriangleHit());

    int3 cellPos = getCellPos(v.posW, gScene.camera.getPosition(), config.cellUnit);
    if (!isCellValid(cellPos))
        return;

    uint flattenIndex = getFlattenCellIndex(cellPos);
    CellInfo cellInfo = gCellInfoBuffer[flattenIndex];

    // Visualize
    float3 topColor = float3(0, 0, 0);
    uint top = 0;
    bool noSurfel = true;

    for (uint i = 0; i < cellInfo.surfelCount; ++i)
    {
        uint surfelIndex = gCellToSurfelBuffer[cellInfo.cellToSurfelBufferOffset + i];
        Surfel surfel = gSurfelBuffer[surfelIndex];

        // TODO: For testing...
        if (surfel.rayCount == 0)
            continue;

        float3 bias = v.posW - surfel.position;
        float dist2 = dot(bias, bias);

        if (dist2 < pow(surfel.radius * gSurfelVisualRadius, 2))
        {
            float3 normal = normalize(surfel.normal);

            float dotN = dot(v.normalW, normal);
            if (dotN > 0)
            {
                if (surfelIndex > top)
                {
                    topColor = float3(0, 0, 0);
                    for (uint rayIndex = 0; rayIndex < surfel.rayCount; ++rayIndex)
                    {
                        float3 radiance = gSurfelRayBuffer[surfel.rayOffset + rayIndex].radiance;
                        topColor += (1.f / surfel.rayCount) * (radiance - topColor);
                    }

                    top = surfelIndex;
                    noSurfel = false;
                }
            }
        }
    }

    gOutput[pixelPos] = float4(topColor, noSurfel ? 0 : 1);
}

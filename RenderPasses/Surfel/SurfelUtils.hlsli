#ifndef SURFEL_UTILS_H
#define SURFEL_UTILS_H

#include "SurfelTypes.hlsli"

static const int3 neighborOffset[27] =
{
    int3(-1, -1, -1),
    int3(-1, -1, 0),
    int3(-1, -1, 1),
    int3(-1, 0, -1),
    int3(-1, 0, 0),
    int3(-1, 0, 1),
    int3(-1, 1, -1),
    int3(-1, 1, 0),
    int3(-1, 1, 1),
    int3(0, -1, -1),
    int3(0, -1, 0),
    int3(0, -1, 1),
    int3(0, 0, -1),
    int3(0, 0, 0),
    int3(0, 0, 1),
    int3(0, 1, -1),
    int3(0, 1, 0),
    int3(0, 1, 1),
    int3(1, -1, -1),
    int3(1, -1, 0),
    int3(1, -1, 1),
    int3(1, 0, -1),
    int3(1, 0, 0),
    int3(1, 0, 1),
    int3(1, 1, -1),
    int3(1, 1, 0),
    int3(1, 1, 1),
};

float3 unProject(float2 uv, float depth, float4x4 invViewProj)
{
    float x = uv.x * 2 - 1;
    float y = (1 - uv.y) * 2 - 1;
    float4 pos = mul(invViewProj, float4(x, y, depth, 1));

    return pos.xyz / pos.w;
}

int3 getCellPos(float3 posW, float3 cameraPosW)
{
    float3 posC = posW - cameraPosW;
    posC /= kCellUnit;
    return (int3)round(posC);
}

uint getFlattenCellIndex(int3 cellPos)
{
    uint3 unsignedPos = cellPos + kCellDimension / 2;
    return (unsignedPos.z * kCellDimension.x * kCellDimension.y) + (unsignedPos.y * kCellDimension.x) + unsignedPos.x;
}

bool isCellValid(int3 cellPos)
{
    if (abs(cellPos.x) > kCellDimension.x / 2)
        return false;
    if (abs(cellPos.y) > kCellDimension.y / 2)
        return false;
    if (abs(cellPos.z) > kCellDimension.z / 2)
        return false;

    return true;
}

bool isSurfelIntersectCell(Surfel surfel, int3 cellPos, float3 cameraPosW)
{
    if (!isCellValid(cellPos))
        return false;

    float3 minPosW = cellPos * kCellUnit - float3(kCellUnit, kCellCount, kCellCount) / 2.0f + cameraPosW;
    float3 maxPosW = cellPos * kCellUnit + float3(kCellUnit, kCellCount, kCellCount) / 2.0f + cameraPosW;
    float3 closePoint = min(max(surfel.position, minPosW), maxPosW);

    float dist = distance(closePoint, surfel.position);
    return dist < kSurfelRadius;
}

#endif

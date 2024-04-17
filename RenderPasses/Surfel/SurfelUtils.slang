#pragma once
#define PI 3.14159265f

import RenderPasses.Surfel.SurfelTypes;
import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.HashUtils;

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

float calcProjectArea(float radius, float distance, float fovy, uint2 resolution)
{
    float projRadius = atan(radius / distance) * max(resolution.x, resolution.y) / fovy;
    return PI * projRadius * projRadius;
}

float calcRadiusApprox(float area, float distance, float fovy, uint2 resolution)
{
    return distance * tan(sqrt(area / PI) * fovy / max(resolution.x, resolution.y));
}

float calcRadius(float area, float distance, float fovy, uint2 resolution)
{
    float cosTheta = 1 - (area * (1 - cos(fovy / 2)) / PI) / (resolution.x * resolution.y);
    float sinTheta = sqrt(1 - pow(cosTheta, 2));
    return distance * sinTheta;
}

float calcSurfelRadius(float distance, float fovy, uint2 resolution, float area, float cellUnit)
{
    if (kVariableSurfelRadius)
        return min(calcRadiusApprox(area, distance, fovy, resolution), cellUnit);

    return kStaticSurfelRadius;
}

float3 randomizeColor(float3 color, inout RNG randomState)
{
    float3 randomColor = randomState.next_float3();
    float strength = clamp(length(randomColor), 0.1f, 0.9f);

    return 0.99f * (color * strength) + 0.01f * randomColor;
}

int3 getCellPos(float3 posW, float3 cameraPosW, float cellUnit)
{
    float3 posC = posW - cameraPosW;
    posC /= cellUnit;
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

bool isSurfelIntersectCell(Surfel surfel, int3 cellPos, float3 cameraPosW, float cellUnit)
{
    if (!isCellValid(cellPos))
        return false;

    float3 minPosW = cellPos * cellUnit - float3(cellUnit, cellUnit, cellUnit) / 2.0f + cameraPosW;
    float3 maxPosW = cellPos * cellUnit + float3(cellUnit, cellUnit, cellUnit) / 2.0f + cameraPosW;
    float3 closePoint = min(max(surfel.position, minPosW), maxPosW);

    float dist = distance(closePoint, surfel.position);
    return dist < surfel.radius;
}

float3 pseudocolor(uint value)
{
    uint h = jenkinsHash(value);
    return (uint3(h, h >> 8, h >> 16) & 0xff) / 255.f;
}

#pragma once
#include "Utils/Math/MathConstants.slangh"

import RenderPasses.Surfel.Random;
import RenderPasses.Surfel.SurfelGI.SurfelTypes;
import RenderPasses.Surfel.SurfelGI.StaticParams;

static const int3 neighborOffset[125] =
{
    int3(-2, -2, -2)    ,
    int3(-2, -2, -1)    ,
    int3(-2, -2, 0)     ,
    int3(-2, -2, 1)     ,
    int3(-2, -2, 2)     ,
    int3(-2, -1, -2)    ,
    int3(-2, -1, -1)    ,
    int3(-2, -1, 0)     ,
    int3(-2, -1, 1)     ,
    int3(-2, -1, 2)     ,
    int3(-2, 0, -2)     ,
    int3(-2, 0, -1)     ,
    int3(-2, 0, 0)      ,
    int3(-2, 0, 1)      ,
    int3(-2, 0, 2)      ,
    int3(-2, 1, -2)     ,
    int3(-2, 1, -1)     ,
    int3(-2, 1, 0)      ,
    int3(-2, 1, 1)      ,
    int3(-2, 1, 2)      ,
    int3(-2, 2, -2)     ,
    int3(-2, 2, -1)     ,
    int3(-2, 2, 0)      ,
    int3(-2, 2, 1)      ,
    int3(-2, 2, 2)      ,
    int3(-1, -2, -2)    ,
    int3(-1, -2, -1)    ,
    int3(-1, -2, 0)     ,
    int3(-1, -2, 1)     ,
    int3(-1, -2, 2)     ,
    int3(-1, -1, -2)    ,
    int3(-1, -1, -1)    ,
    int3(-1, -1, 0)     ,
    int3(-1, -1, 1)     ,
    int3(-1, -1, 2)     ,
    int3(-1, 0, -2)     ,
    int3(-1, 0, -1)     ,
    int3(-1, 0, 0)      ,
    int3(-1, 0, 1)      ,
    int3(-1, 0, 2)      ,
    int3(-1, 1, -2)     ,
    int3(-1, 1, -1)     ,
    int3(-1, 1, 0)      ,
    int3(-1, 1, 1)      ,
    int3(-1, 1, 2)      ,
    int3(-1, 2, -2)     ,
    int3(-1, 2, -1)     ,
    int3(-1, 2, 0)      ,
    int3(-1, 2, 1)      ,
    int3(-1, 2, 2)      ,
    int3(0, -2, -2)     ,
    int3(0, -2, -1)     ,
    int3(0, -2, 0)      ,
    int3(0, -2, 1)      ,
    int3(0, -2, 2)      ,
    int3(0, -1, -2)     ,
    int3(0, -1, -1)     ,
    int3(0, -1, 0)      ,
    int3(0, -1, 1)      ,
    int3(0, -1, 2)      ,
    int3(0, 0, -2)      ,
    int3(0, 0, -1)      ,
    int3(0, 0, 0)       ,
    int3(0, 0, 1)       ,
    int3(0, 0, 2)       ,
    int3(0, 1, -2)      ,
    int3(0, 1, -1)      ,
    int3(0, 1, 0)       ,
    int3(0, 1, 1)       ,
    int3(0, 1, 2)       ,
    int3(0, 2, -2)      ,
    int3(0, 2, -1)      ,
    int3(0, 2, 0)       ,
    int3(0, 2, 1)       ,
    int3(0, 2, 2)       ,
    int3(1, -2, -2)     ,
    int3(1, -2, -1)     ,
    int3(1, -2, 0)      ,
    int3(1, -2, 1)      ,
    int3(1, -2, 2)      ,
    int3(1, -1, -2)     ,
    int3(1, -1, -1)     ,
    int3(1, -1, 0)      ,
    int3(1, -1, 1)      ,
    int3(1, -1, 2)      ,
    int3(1, 0, -2)      ,
    int3(1, 0, -1)      ,
    int3(1, 0, 0)       ,
    int3(1, 0, 1)       ,
    int3(1, 0, 2)       ,
    int3(1, 1, -2)      ,
    int3(1, 1, -1)      ,
    int3(1, 1, 0)       ,
    int3(1, 1, 1)       ,
    int3(1, 1, 2)       ,
    int3(1, 2, -2)      ,
    int3(1, 2, -1)      ,
    int3(1, 2, 0)       ,
    int3(1, 2, 1)       ,
    int3(1, 2, 2)       ,
    int3(2, -2, -2)     ,
    int3(2, -2, -1)     ,
    int3(2, -2, 0)      ,
    int3(2, -2, 1)      ,
    int3(2, -2, 2)      ,
    int3(2, -1, -2)     ,
    int3(2, -1, -1)     ,
    int3(2, -1, 0)      ,
    int3(2, -1, 1)      ,
    int3(2, -1, 2)      ,
    int3(2, 0, -2)      ,
    int3(2, 0, -1)      ,
    int3(2, 0, 0)       ,
    int3(2, 0, 1)       ,
    int3(2, 0, 2)       ,
    int3(2, 1, -2)      ,
    int3(2, 1, -1)      ,
    int3(2, 1, 0)       ,
    int3(2, 1, 1)       ,
    int3(2, 1, 2)       ,
    int3(2, 2, -2)      ,
    int3(2, 2, -1)      ,
    int3(2, 2, 0)       ,
    int3(2, 2, 1)       ,
    int3(2, 2, 2)       
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
    return M_PI * projRadius * projRadius;
}

float calcRadiusApprox(float area, float distance, float fovy, uint2 resolution)
{
    return distance * tan(sqrt(area / M_PI) * fovy / max(resolution.x, resolution.y));
}

float calcRadius(float area, float distance, float fovy, uint2 resolution)
{
    float cosTheta = 1 - (area * (1 - cos(fovy / 2)) / M_PI) / (resolution.x * resolution.y);
    float sinTheta = sqrt(1 - pow(cosTheta, 2));
    return distance * sinTheta;
}

float calcSurfelRadius(float distance, float fovy, uint2 resolution, float area, float cellUnit)
{
    return min(calcRadiusApprox(area, distance, fovy, resolution), cellUnit * 2);
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
    uint3 unsignedPos = cellPos + uint3(kCellDimension / 2);
    return (unsignedPos.z * kCellDimension * kCellDimension) + (unsignedPos.y * kCellDimension) + unsignedPos.x;
}

bool isCellValid(int3 cellPos)
{
    if (abs(cellPos.x) >= kCellDimension / 2)
        return false;
    if (abs(cellPos.y) >= kCellDimension / 2)
        return false;
    if (abs(cellPos.z) >= kCellDimension / 2)
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

float3x3 get_tangentspace(in float3 normal)
{
    float3 helper = abs(normal.x) > 0.99 ? float3(0, 0, 1) : float3(1, 0, 0);

    float3 tangent = normalize(cross(normal, helper));
    float3 binormal = normalize(cross(normal, tangent));
    return float3x3(tangent, binormal, normal);
}

float3 hemispherepoint_uniform(float u, float v) {
    float phi = v * 2 * M_PI;
    float cosTheta = 1 - u;
    float sinTheta = sqrt(1 - cosTheta * cosTheta);
    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

float3 hemispherepoint_cos(float u, float v) {
    float phi = v * 2 * M_PI;
    float cosTheta = sqrt(1 - u);
    float sinTheta = sqrt(1 - cosTheta * cosTheta);
    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

float3 sample_hemisphere_uniform(in float3 normal, inout RNG rng)
{
    return mul(hemispherepoint_uniform(rng.next_float(), rng.next_float()), get_tangentspace(normal));
}

float3 sample_hemisphere_cos(in float3 normal, inout RNG rng)
{
    return mul(hemispherepoint_cos(rng.next_float(), rng.next_float()), get_tangentspace(normal));
}

// Octahedral Normal Vectors (ONV) Encode & Decode.
// Modified for hemisphere projection.
// https://jcgt.org/published/0003/02/01/
float2 octEncode(float3 v)
{
    float l1norm = abs(v.x) + abs(v.y) + abs(v.z);
    float2 result = v.xy * (1.f / l1norm);
    return float2(result.x - result.y, result.x + result.y);
}

float3 octDecode(float2 uv)
{
    float2 result = float2((uv.x + uv.y) / 2.f, (uv.y - uv.x) / 2.f);
    float3 v = float3(result.x, result.y, 1.f - abs(result.x) - abs(result.y));
    return normalize(v);
}

float3 lerpColor(float t)
{
    float3 color;
    float normalizedT;

    if (t <= 0.5f)
    {
        normalizedT = t / 0.5f;
        return float3(0.f, normalizedT, 1.f - normalizedT);
    }

    normalizedT = (t - 0.5f) / 0.5f;
    return float3(normalizedT, 1.f - normalizedT, 0.f);
}

float3 stepColor(float t, float r, float g)
{
    if (t > r)
        return float3(1, 0, 0);
    else if (t > g)
        return float3(0, 1, 0);
    else
        return float3(0, 0, 1);
}

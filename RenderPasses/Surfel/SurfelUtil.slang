#pragma once

float3 unProject(float2 uv, float32_t depth, float4x4 invViewProj)
{
    float x = uv.x * 2 - 1;
    float y = (1 - uv.y) * 2 - 1;
    float4 pos = mul(invViewProj, float4(x, y, depth, 1));

    return pos.xyz / pos.w;
}

namespace Random
{
typedef uint2 State;

uint rotl(uint x, uint k) { return (x << k) | (x >> (32 - k)); }

uint hash(uint seed)
{
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

uint next(inout State s)
{
    uint result = s.x * 0x9e3779bb;

    s.y ^= s.x;
    s.x = rotl(s.x, 26) ^ s.y ^ (s.y << 9);
    s.y = rotl(s.y, 13);

    return result;
}

State init(uint2 id, uint frameIndex)
{
    id += uint2(frameIndex);
    uint s0 = (id.x << 16) | id.y;
    uint s1 = frameIndex;
    return uint2(hash(s0), hash(s1));
}

float nextFloat(inout State s)
{
    uint u = 0x3f800000 | (next(s) >> 9);
    return asfloat(u) - 1.0;
}

float3 nextFloat3(inout State s)
{
    float x = nextFloat(s);
    float y = nextFloat(s);
    float z = nextFloat(s);

    return float3(x, y, z);
}

uint nextUint(inout State s, uint maxValue)
{
    float f = nextFloat(s);
    return uint(floor(f * maxValue));
}

} // namespace Random

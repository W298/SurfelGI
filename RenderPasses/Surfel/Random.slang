#pragma once

struct RNG
{
    uint2 s;

    uint rotl(uint x, uint k)
    {
        return (x << k) | (x >> (32 - k));
    }

    [mutating]
    uint next()
    {
        uint result = s.x * 0x9e3779bb;

        s.y ^= s.x;
        s.x = rotl(s.x, 26) ^ s.y ^ (s.y << 9);
        s.y = rotl(s.y, 13);

        return result;
    }

    uint hash(uint seed)
    {
        seed = (seed ^ 61) ^ (seed >> 16);
        seed *= 9;
        seed = seed ^ (seed >> 4);
        seed *= 0x27d4eb2d;
        seed = seed ^ (seed >> 15);
        return seed;
    }

    [mutating]
    void init(uint2 id, uint frameIndex)
    {
        id += uint2(frameIndex, frameIndex);
        uint s0 = (id.x << 16) | id.y;
        uint s1 = frameIndex;
        s.x = hash(s0);
        s.y = hash(s1);
        next();
    }

    [mutating]
    float next_float()
    {
        uint u = 0x3f800000 | (next() >> 9);
        return asfloat(u) - 1.0;
    }

    [mutating]
    uint next_uint(uint nmax)
    {
        float f = next_float();
        return uint(floor(f * nmax));
    }

    [mutating]
    float2 next_float2()
    {
        return float2(next_float(), next_float());
    }

    [mutating]
    float3 next_float3()
    {
        return float3(next_float(), next_float(), next_float());
    }
};

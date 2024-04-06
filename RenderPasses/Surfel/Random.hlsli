#ifndef RANDOM_H
#define RANDOM_H

typedef uint2 RandomState;

uint _rotl(uint x, uint k)
{
    return (x << k) | (x >> (32 - k));
}

uint _hash(uint seed)
{
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

uint _next(inout RandomState s)
{
    uint result = s.x * 0x9e3779bb;

    s.y ^= s.x;
    s.x = _rotl(s.x, 26) ^ s.y ^ (s.y << 9);
    s.y = _rotl(s.y, 13);

    return result;
}

RandomState initRandomState(uint2 id, uint frameIndex)
{
    id += uint2(frameIndex, frameIndex);
    uint s0 = (id.x << 16) | id.y;
    uint s1 = frameIndex;
    return uint2(_hash(s0), _hash(s1));
}

float getNextFloat(inout RandomState s)
{
    uint u = 0x3f800000 | (_next(s) >> 9);
    return asfloat(u) - 1.0;
}

float3 getNextFloat3(inout RandomState s)
{
    float x = getNextFloat(s);
    float y = getNextFloat(s);
    float z = getNextFloat(s);

    return float3(x, y, z);
}

uint getNextUInt(inout RandomState s, uint maxValue)
{
    float f = getNextFloat(s);
    return uint(floor(f * maxValue));
}

#endif

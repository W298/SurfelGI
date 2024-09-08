cbuffer CB
{
    uint2 gResolution;
	float gSigmaD;
	float gSigmaR;
};

Texture2D<float4> gInput;
RWTexture2D<float4> gOutput;

#define MINF asfloat(0xff800000)

float gaussR(float sigma, float dist)
{
	return exp(-(dist*dist)/(2.0*sigma*sigma));
}

float  gaussD(float sigma, int x, int y)
{
	return exp(-((x*x+y*y)/(2.0f*sigma*sigma)));
}

[numthreads(16, 16, 1)]
void csMain(int3 dTid : SV_DispatchThreadID)
{
    int kernelRadius = (int)ceil(2.0 * gSigmaD);
	int kernelSize = 2*kernelRadius+1;
	
	float3 sum = float3(0.0f, 0.0f, 0.0f);
	float sumWeight = 0.0f;

    gOutput[dTid.xy] = float4(MINF, MINF, MINF, MINF);

    float4 intCenter = gInput[dTid.xy];
	if(intCenter.x != MINF)
	{
		for(int m = dTid.x-kernelRadius; m <= dTid.x+kernelRadius; m++)
		{
			for(int n = dTid.y-kernelRadius; n <= dTid.y+kernelRadius; n++)
            {
                if (m >= 0 && n >= 0 && m < gResolution.x && n < gResolution.y)
				{
                    uint2 pos = uint2(m, n);
                    float4 intKerPos = gInput[pos];

					if(intKerPos.x != MINF)
					{
                        float d = distance(intKerPos.xyz, intCenter.xyz);
                        float weight = gaussD(gSigmaD, m - dTid.x, n - dTid.y) * gaussR(gSigmaR, d);

						sumWeight += weight;
						sum += weight*intKerPos.xyz;
					}
				}
			}
		}

		if(sumWeight > 0.0f)
        {
            gOutput[dTid.xy] = float4(sum / sumWeight, 1.0f);
		}
	}
}

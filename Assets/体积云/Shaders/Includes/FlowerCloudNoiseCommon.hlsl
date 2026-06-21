#ifndef FLOWER_CLOUD_NOISE_COMMON_INCLUDED
#define FLOWER_CLOUD_NOISE_COMMON_INCLUDED

// HLSL port of flower/install/shader/cloud_noise_common.glsl.
// The unsigned integer hash deliberately keeps uint overflow/wrapping behavior.

static const uint3 FLOWER_UI3 =
    uint3(1597334673u, 3812015801u, 2798796415u);

static const float FLOWER_UIF =
    1.0 / 4294967295.0;

float3 FlowerPositiveMod(float3 value, float divisor)
{
    return value - divisor * floor(value / divisor);
}

float3 FlowerHash33(float3 position)
{
    uint3 q = uint3(int3(position)) * FLOWER_UI3;
    q = (q.x ^ q.y ^ q.z) * FLOWER_UI3;

    return -1.0 + 2.0 * float3(q) * FLOWER_UIF;
}

// Tileable 3D gradient noise.
float FlowerGradientNoise(float3 position, float frequency)
{
    float3 cell = floor(position);
    float3 localPosition = frac(position);

    // Quintic interpolation curve.
    float3 blend =
        localPosition * localPosition * localPosition
        * (localPosition * (localPosition * 6.0 - 15.0) + 10.0);

    float3 g000 = FlowerHash33(
        FlowerPositiveMod(cell + float3(0.0, 0.0, 0.0), frequency)
    );
    float3 g100 = FlowerHash33(
        FlowerPositiveMod(cell + float3(1.0, 0.0, 0.0), frequency)
    );
    float3 g010 = FlowerHash33(
        FlowerPositiveMod(cell + float3(0.0, 1.0, 0.0), frequency)
    );
    float3 g110 = FlowerHash33(
        FlowerPositiveMod(cell + float3(1.0, 1.0, 0.0), frequency)
    );
    float3 g001 = FlowerHash33(
        FlowerPositiveMod(cell + float3(0.0, 0.0, 1.0), frequency)
    );
    float3 g101 = FlowerHash33(
        FlowerPositiveMod(cell + float3(1.0, 0.0, 1.0), frequency)
    );
    float3 g011 = FlowerHash33(
        FlowerPositiveMod(cell + float3(0.0, 1.0, 1.0), frequency)
    );
    float3 g111 = FlowerHash33(
        FlowerPositiveMod(cell + float3(1.0, 1.0, 1.0), frequency)
    );

    float v000 = dot(g000, localPosition - float3(0.0, 0.0, 0.0));
    float v100 = dot(g100, localPosition - float3(1.0, 0.0, 0.0));
    float v010 = dot(g010, localPosition - float3(0.0, 1.0, 0.0));
    float v110 = dot(g110, localPosition - float3(1.0, 1.0, 0.0));
    float v001 = dot(g001, localPosition - float3(0.0, 0.0, 1.0));
    float v101 = dot(g101, localPosition - float3(1.0, 0.0, 1.0));
    float v011 = dot(g011, localPosition - float3(0.0, 1.0, 1.0));
    float v111 = dot(g111, localPosition - float3(1.0, 1.0, 1.0));

    return
        v000
        + blend.x * (v100 - v000)
        + blend.y * (v010 - v000)
        + blend.z * (v001 - v000)
        + blend.x * blend.y * (v000 - v100 - v010 + v110)
        + blend.y * blend.z * (v000 - v010 - v001 + v011)
        + blend.z * blend.x * (v000 - v100 - v001 + v101)
        + blend.x * blend.y * blend.z
        * (-v000 + v100 + v010 - v110 + v001 - v101 - v011 + v111);
}

// Tileable inverted 3D Worley noise.
float FlowerWorleyNoise(float3 uv, float frequency)
{
    float3 cell = floor(uv);
    float3 localPosition = frac(uv);

    float minimumDistanceSquared = 10000.0;

    [unroll]
    for (int x = -1; x <= 1; x++)
    {
        [unroll]
        for (int y = -1; y <= 1; y++)
        {
            [unroll]
            for (int z = -1; z <= 1; z++)
            {
                float3 offset = float3(x, y, z);

                float3 featurePoint = FlowerHash33(
                    FlowerPositiveMod(
                        cell + offset,
                        frequency
                    )
                ) * 0.5 + 0.5;

                featurePoint += offset;

                float3 difference =
                    localPosition - featurePoint;

                minimumDistanceSquared = min(
                    minimumDistanceSquared,
                    dot(difference, difference)
                );
            }
        }
    }

    return 1.0 - minimumDistanceSquared;
}

float FlowerPerlinFBM(
    float3 position,
    float frequency,
    int octaveCount)
{
    const float amplitudeFalloff = exp2(-0.85);

    float amplitude = 1.0;
    float noise = 0.0;

    [loop]
    for (int octave = 0; octave < octaveCount; octave++)
    {
        noise += amplitude * FlowerGradientNoise(
            position * frequency,
            frequency
        );

        frequency *= 2.0;
        amplitude *= amplitudeFalloff;
    }

    return noise;
}

float FlowerWorleyFBM(float3 position, float frequency)
{
    return
        FlowerWorleyNoise(
            position * frequency,
            frequency
        ) * 0.625
        + FlowerWorleyNoise(
            position * frequency * 2.0,
            frequency * 2.0
        ) * 0.25
        + FlowerWorleyNoise(
            position * frequency * 4.0,
            frequency * 4.0
        ) * 0.125;
}

float FlowerRemap(
    float value,
    float sourceMinimum,
    float sourceMaximum,
    float targetMinimum,
    float targetMaximum)
{
    return
        ((value - sourceMinimum)
        / (sourceMaximum - sourceMinimum))
        * (targetMaximum - targetMinimum)
        + targetMinimum;
}

#endif

const float minWavelength = 380.0;
const float maxWavelength = 720.0;
const float rangeWavelengths = maxWavelength - minWavelength;

// Piecewise Gaussian
float G(float x, float mu, float T1, float T2) {
    float t = (x < mu ? T1 : T2) * (x - mu);
    return exp(-t*t/2);
}

// wavelengthToXYZ from PLTFalcor
vec3 wavelengthToXYZ(float lambda) {
    float x = 0.362f * G(lambda, 442.0f, 0.0624f, 0.0374f) + 1.056f * G(lambda, 599.8f, 0.0264f, 0.0323f) - 0.065f * G(lambda, 501.1f, 0.0490f, 0.0382f);
    float y = 0.821f * G(lambda, 568.8f, 0.0213f, 0.0247f) + 0.286f * G(lambda, 530.9f, 0.0613f, 0.0322f);
    float z = 1.217f * G(lambda, 437.0f, 0.0845f, 0.0278f) + 0.681f * G(lambda, 459.0f, 0.0385f, 0.0725f);
    return vec3(x, y, z);
}
const float D65_5nm[69] = float[69](49.9755,52.3118,54.6482,68.7015,82.7549,87.1204,91.486,92.4589,93.4318,90.057,86.6823,95.7736,104.865,110.936,
    117.008,117.41,117.812,116.336,114.861,115.392,115.923,112.367,108.811,109.082,109.354,108.578,107.802,106.296,
    104.79,106.239,107.689,106.047,104.405,104.225,104.046,102.023,100.,98.1671,96.3342,96.0611,95.788,92.2368,88.6856,
    89.3459,90.0062,89.8026,89.5991,88.6489,87.6987,85.4936,83.2886,83.4939,83.6992,81.863,80.0268,80.1207,80.2146,
    81.2462,82.2778,80.281,78.2842,74.0027,69.7213,70.6652,71.6091,72.979,74.349,67.9765,61.604
);
// wavelengthToD65 from PLTFalcor
float wavelengthToD65(float lambda) {
    const float wavelengthResize = (lambda - minWavelength) * 0.2f;
    const int wavelength_t = int(ceil(wavelengthResize)+.5f);
    const int wavelength_b = int(floor(wavelengthResize)+.5f);
    const float weight = wavelengthResize - wavelength_b;
    return D65_5nm[wavelength_t] * weight + D65_5nm[wavelength_b] * (1.0f - weight);
}

// XYZtoRGB_Rec709 from PLTFalcor
vec3 XYZtoRGB_Rec709(vec3 c) {
    const mat3 M = mat3(
        3.240969941904522, -1.537383177570094, -0.4986107602930032,
        -0.9692436362808803, 1.875967501507721, 0.04155505740717569,
        0.05563007969699373, -0.2039769588889765, 1.056971514242878
    );
    return transpose(M) * c;
}

vec3 XYZtoSRGB_linear(vec3 c) {
    const mat3 M = mat3(
        3.240969941904523, -1.537383177570094, -0.498610760293003,
        -0.969243636280880, 1.875967501507721, 0.041555057407176,
        0.055630079696994, -0.203976958888977, 1.056971514242879
    );
    return transpose(M) * c;
}

// spectrumToRgb adapted from PLTFalcor
vec3 spectrumToRgb(float wavelength) {
    vec3 xyz = wavelengthToXYZ(wavelength) * wavelengthToD65(wavelength);

    const float Y_D65 = 10.5670762f;
    return XYZtoSRGB_linear(xyz) / Y_D65;
}

const float white_sd[11] = float[11](1,1,0.9999,0.9993,0.9992,0.9998,1,1,1,1,0);
const float cyan_sd[11] = float[11](0.9710,0.9426,1.0007,1.0007,1.0007,1.0007,0.1564,0,0,0,0);
const float magenta_sd[11] = float[11](1,1,0.968, 0.22295,0,0.0458,0.8369,1,1,0.9959,0);
const float yellow_sd[11] = float[11](0.0001,0,0.1088,0.6651,1,1,0.9996,0.9586,0.9685,0.9840,0);
const float red_sd[11] = float[11](0.1012,0.0515,0,0,0,0,0.8325,1.0149,1.0149,1.014,0);
const float green_sd[11] = float[11](0,0,0.0273,0.7937,1,0.9418,0.1719,0,0,0.0025,0);
const float blue_sd[11] = float[11](1,1,0.8916,0.3323,0,0,0.0003,0.0369,0.0483,0.0496,0);

// adapted from rgbToSpectrum from PLTFalcor
float rgb_to_spectrum(vec3 rgb, float wavelength) {
    float sd = 0.0;
    const int b = int(clamp((wavelength - minWavelength) / rangeWavelengths, 0.0, 1.0) * 10.0);
    const float white_s   = white_sd[b];
    const float cyan_s    = cyan_sd[b];
    const float magenta_s = magenta_sd[b];
    const float yellow_s  = yellow_sd[b];
    const float red_s     = red_sd[b];
    const float green_s   = green_sd[b];
    const float blue_s    = blue_sd[b];
    const float red = rgb.x;
    const float green = rgb.y;
    const float blue = rgb.z;
    if (red <= green && red <= blue) {
        sd += white_s * red;
        if (green <= blue) {
            sd += cyan_s * (green - red);
            sd += blue_s * (blue - green);
        } else {
            sd += cyan_s * (blue - red);
            sd += green_s * (green - blue);
        }
    } else if (green <= red && green <= blue) {
        sd += white_s * green;
        if (red <= blue) {
            sd += magenta_s * (red - green);
            sd += blue_s * (blue - red);
        } else {
            sd += magenta_s * (blue - green);
            sd += red_s * (red - blue);
        }
    } else {
        sd += white_s * blue;
        if (red <= green) {
            sd += yellow_s * (red - blue);
            sd += green_s * (green - red);
        } else {
            sd += yellow_s * (green - blue);
            sd += red_s * (red - green);
        }
    }
    return sd;
}

//By Björn Ottosson
//https://bottosson.github.io/posts/oklab
//Shader functions adapted by "mattz"
//https://www.shadertoy.com/view/WtccD7

vec3 oklab_from_linear(vec3 linear)
{
    const mat3 im1 = mat3(0.4122214708, 0.2119034982, 0.0883097947,
                          0.5363325363, 0.6806995451, 0.2817188376,
                          0.0514459929, 0.1073969566, 0.6299787005);

    const mat3 im2 = mat3(+0.2104542553, +1.9779984951, +0.0259040371,
                          +0.7936177850, -2.4285922050, +0.7827717662,
                          -0.0040720468, +0.4505937099, -0.8086757660);

    vec3 lms = im1 * linear;

    return im2 * (sign(lms) * pow(abs(lms), vec3(1.0/3.0)));
}

vec3 linear_from_oklab(vec3 oklab)
{
    const mat3 m1 = mat3(+1.000000000, +1.000000000, +1.000000000,
                         +0.3963377774, -0.1055613458, -0.0894841775,
                         +0.2158037573, -0.0638541728, -1.2914855480);

    const mat3 m2 = mat3(+4.0767416621, -1.2684380046, -0.0041960863,
                         -3.3077115913, +2.6097574011, -0.7034186147,
                         +0.2309699292, -0.3413193965, +1.7076147010);
    vec3 lms = m1 * oklab;

    return m2 * (lms * lms * lms);
}

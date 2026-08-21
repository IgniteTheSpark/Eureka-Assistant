#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uFlowDirection;
uniform float uWaveSpeed;
uniform float uWaveFrequency;
uniform float uWaveAmplitude;
uniform vec3 uWaveColor;
uniform float uOpacity;
uniform float uColorNum;
uniform float uPixelSize;
uniform float uDisplacementStrength;
uniform float uSourceCount;
uniform vec4 uSourceRects[24];
uniform vec2 uSourceMeta[24];

out vec4 fragColor;

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

vec2 fade2(vec2 t) {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float cnoise(vec2 p) {
  vec4 pi = floor(p.xyxy) + vec4(0.0, 0.0, 1.0, 1.0);
  vec4 pf = fract(p.xyxy) - vec4(0.0, 0.0, 1.0, 1.0);
  pi = mod289(pi);
  vec4 ix = pi.xzxz;
  vec4 iy = pi.yyww;
  vec4 fx = pf.xzxz;
  vec4 fy = pf.yyww;
  vec4 i = permute(permute(ix) + iy);
  vec4 gx = fract(i * (1.0 / 41.0)) * 2.0 - 1.0;
  vec4 gy = abs(gx) - 0.5;
  vec4 tx = floor(gx + 0.5);
  gx -= tx;
  vec2 g00 = vec2(gx.x, gy.x);
  vec2 g10 = vec2(gx.y, gy.y);
  vec2 g01 = vec2(gx.z, gy.z);
  vec2 g11 = vec2(gx.w, gy.w);
  vec4 norm = taylorInvSqrt(
    vec4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11))
  );
  g00 *= norm.x;
  g01 *= norm.y;
  g10 *= norm.z;
  g11 *= norm.w;
  float n00 = dot(g00, vec2(fx.x, fy.x));
  float n10 = dot(g10, vec2(fx.y, fy.y));
  float n01 = dot(g01, vec2(fx.z, fy.z));
  float n11 = dot(g11, vec2(fx.w, fy.w));
  vec2 fxy = fade2(pf.xy);
  vec2 nx = mix(vec2(n00, n01), vec2(n10, n11), fxy.x);
  return 2.3 * mix(nx.x, nx.y, fxy.y);
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 1.0;
  float frequency = uWaveFrequency;
  for (int octave = 0; octave < 4; octave++) {
    value += amplitude * abs(cnoise(p));
    p *= frequency;
    amplitude *= uWaveAmplitude;
  }
  return value;
}

float bayer2(vec2 point) {
  float x = mod(floor(point.x), 2.0);
  float y = mod(floor(point.y), 2.0);
  float top = mix(0.0, 3.0, x);
  float bottom = mix(2.0, 1.0, x);
  return mix(top, bottom, y);
}

float bayer8(ivec2 point) {
  vec2 p = vec2(point);
  float value = 16.0 * bayer2(p);
  value += 4.0 * bayer2(floor(p / 2.0));
  value += bayer2(floor(p / 4.0));
  return (value + 0.5) / 64.0;
}

float sourceDistance(vec2 point, vec4 rect, float shape) {
  vec2 delta = point - rect.xy;
  if (shape < 0.5) {
    return length(delta) - rect.z;
  }
  float radius = rect.w;
  float segment = max(0.0, rect.z - radius);
  delta.x -= clamp(delta.x, -segment, segment);
  return length(delta) - radius;
}

float displacement(vec2 point) {
  float pressure = 0.0;
  for (int index = 0; index < 24; index++) {
    if (float(index) >= uSourceCount) {
      continue;
    }
    vec4 rect = uSourceRects[index];
    vec2 meta = uSourceMeta[index];
    float diameter = min(rect.z, rect.w) * 2.0;
    float spread = clamp(meta.y, 0.0, 1.0) * clamp(diameter * 0.34, 18.0, 24.0);
    float distance = sourceDistance(point, rect, meta.x) - spread;
    float feather = clamp(min(rect.z, rect.w) * 0.44, 4.0, 14.0) + spread * 0.35;
    float influence = 1.0 - smoothstep(-feather, feather, distance);
    pressure = max(pressure, influence * (1.0 + meta.y * 0.18));
  }
  return clamp(pressure, 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize - 0.5;
  uv.x *= uSize.x / max(1.0, uSize.y);
  vec2 flow = normalize(uFlowDirection + vec2(0.0001));
  vec2 shifted = uv - flow * uTime * uWaveSpeed;
  float wave = fbm(uv + fbm(shifted));
  wave -= displacement(frag) * uDisplacementStrength;
  wave = clamp(wave, 0.0, 1.0);

  float levels = max(2.0, uColorNum) - 1.0;
  ivec2 cell = ivec2(floor(frag / uPixelSize));
  float threshold = bayer8(cell);
  float quantized = floor(clamp(wave + (threshold - 0.5) / levels, 0.0, 1.0) * levels + 0.5) / levels;
  vec2 within = mod(frag, uPixelSize);
  float dotSize = max(1.0, uPixelSize * 0.54);
  float squareDot = step(within.x, dotSize) * step(within.y, dotSize);
  float alpha = quantized * squareDot * uOpacity;
  fragColor = vec4(uWaveColor * alpha, alpha);
}

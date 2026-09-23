#include <flutter/runtime_effect.glsl>

// 「流沙」流体场：连续速度场 + 值噪声 + 正弦扭曲 + 颗粒。
//
// 与 now_playing_screen / 圆斑方案的差别：这里没有「几个圆」这种离散物体，
// 整幅画面是一个连续场——每像素的颜色由噪声坐标决定，噪声坐标又被正弦场
// 扭曲，所以看到的是「整片在流」而不是「几个东西在动」。
//
// uTime 必须是**单调递增的秒数**（见 FluidClock）。用 0→1 循环的 controller
// 驱动会让噪声在回绕处瞬间跳变。
//
// uSeed 让**每张卡有自己的流动动画**：它偏移噪声采样点、起始方向与扭曲相位。
// 只给时间相位偏移是不够的——噪声场本身没变，四张卡看起来还是同一个图案。

uniform vec2 uSize;
uniform float uTime;
uniform float uSeed;
uniform float uWarp;
uniform float uGrain;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;
uniform vec3 uColor4;

out vec4 fragColor;

// 值噪声（自有实现；非 Inigo Quilez 代码，避免 CC BY-NC-SA 授权问题）
float hash21(vec2 p) {
  p = fract(p * vec2(127.1, 311.7));
  p += dot(p, p + 34.56);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
             u.y);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float ratio = uSize.x / max(uSize.y, 1.0);
  vec2 p = uv - 0.5;

  // 每张卡采样噪声场的**不同区域** → 图案本身不同（不只是相位差）
  vec2 off = vec2(uSeed * 37.0, uSeed * 91.0);

  // ① 噪声驱动的缓慢自转；起始方向按 seed 错开（seed 由 Dart 侧按 45°/卡 递增）
  float spin = (vnoise(vec2(uTime * 0.05, 3.7) + off) - 0.5) * 5.0 +
               uTime * 0.07 +
               uSeed;
  float c = cos(spin);
  float s = sin(spin);
  vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
  q.y /= ratio;

  // ② 正弦扭曲：连续推进的相位 → 色带持续「翻涌」而不是来回摆动；相位按 seed 错开
  float w = max(uWarp, 0.001);
  float ph = uTime + uSeed * 3.0;
  q.x += sin(q.y * 3.0 + ph * 0.32) / w;
  q.y += sin(q.x * 4.5 - ph * 0.26) / (w * 0.65);

  // ③ 第二层噪声：把色带边界打散成不规则形状（这一步是「沙」的关键，
  //    少了它就只是几条光滑的正弦带）
  float n = vnoise(q * 2.2 + uTime * 0.04 + off);

  vec3 a = mix(uColor1, uColor2,
               smoothstep(-0.55, 0.55, q.x + (n - 0.5) * 0.40));
  vec3 b = mix(uColor3, uColor4,
               smoothstep(-0.55, 0.55, q.x * 1.15 + 0.25 - (n - 0.5) * 0.35));
  vec3 col = mix(a, b, smoothstep(0.55, -0.55, q.y + (n - 0.5) * 0.45));

  // ④ 颗粒：沙粒质感。刻意做成**静态**——动态颗粒会闪，且大时间值下
  //    hash 精度会退化。颗粒也按 seed 错开，避免四张卡沙粒纹路一样。
  float g = hash21(uv * uSize * 0.8 + off);
  col += (g - 0.5) * uGrain;

  fragColor = vec4(col, 1.0);
}

#version 600 es

// Water shimmer for one terrain chunk, reproducing the path-drawn
// travelling highlight: each cell belongs to a diagonal band
// (column - row) % bands, and each band's brightness rises and falls
// out of phase. The chunk's water coverage comes from a mask texture
// recorded alongside the chunk; everything else is computed per pixel
// from world coordinates and time, so the effect costs one textured
// quad per water chunk and no per-frame path work.

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform sampler2D uMask;

uniform float uTime; // ambient seconds
uniform float uPeriod; // shimmer.periodSeconds
uniform float uBands; // shimmer.bands
uniform float uMaxOpacity; // shimmer.maxOpacity
uniform vec4 uTint; // shimmer.colorRgb (rgb; a unused)
uniform vec2 uChunkOrigin; // world position of the quad's top-left
uniform vec2 uLocalSize; // world size of the quad

out vec4 frag_color;

const float tileHalfWidth = 32.0;
const float tileHalfHeight = 16.0;
const float tau = 6.283185307179586;

void main() {
  vec2 fragCoord = FlutterFragCoord();
  float coverage = texture(uMask, fragCoord / uLocalSize).a;
  if (coverage <= 0.0) {
    frag_color = vec4(0.0);
    return;
  }
  // Cell centres sit on lattice points: world.x = (column - row) *
  // tileHalfWidth, world.y = (column + row) * tileHalfHeight.
  // Recover the nearest cell exactly as the renderer's picking math
  // does, then the cell's diagonal band.
  vec2 world = fragCoord + uChunkOrigin;
  float latticeX = world.x / tileHalfWidth;
  float latticeY = world.y / tileHalfHeight;
  float column = floor((latticeX + latticeY) / 2.0 + 0.5);
  float row = floor((latticeY - latticeX) / 2.0 + 0.5);
  float band = mod(column - row, uBands);
  float wave = 0.5 + 0.5 * sin(tau * (uTime / uPeriod) - band * tau / uBands);
  float alpha = wave * uMaxOpacity * coverage;
  if (alpha < 0.006) {
    frag_color = vec4(0.0);
    return;
  }
  frag_color = vec4(uTint.rgb * alpha, alpha);
}

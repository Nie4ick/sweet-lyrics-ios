#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Slow domain warp of the cover art, in the spirit of the Kawarp background Spicy Lyrics uses.
// Returns the position to sample for each destination pixel.
[[ stitchable ]] float2 kawarpWarp(float2 position, float2 size, float time, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float t = time;

    float2 q;
    q.x = sin(uv.y * 3.1 + t * 0.90) + 0.5 * sin(uv.y * 7.3 + uv.x * 2.0 - t * 0.60);
    q.y = cos(uv.x * 2.7 - t * 0.70) + 0.5 * cos(uv.x * 6.1 + uv.y * 3.0 + t * 0.50);

    float2 r;
    r.x = sin((uv.x + q.y * 0.35) * 4.0 + t * 0.40);
    r.y = cos((uv.y + q.x * 0.35) * 4.0 - t * 0.35);

    float scale = min(size.x, size.y) * 0.06 * intensity;
    return position + (q * 0.6 + r * 0.4) * scale;
}

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Liquid Glass over a sharp wallpaper crop, for WallpaperGlass.
//
// The layer is the crop padded by `margin` on every side, so the lens at the rim can pull in
// wallpaper from just outside the panel the way thick glass does. Panel coordinates are
// layer coordinates minus `margin`. The outline is a rounded box with separate top and
// bottom radii; `openTop` pushes the top edge off-screen for panels attached to the screen
// edge, where there is no glass edge to light.

// Signed distance to a box from `lo` to `hi` with radius `rt` on the top corners and `rb`
// on the bottom ones. Negative inside.
static float roundedBox(float2 p, float2 lo, float2 hi, float rt, float rb) {
	float2 c = (lo + hi) * 0.5;
	float2 h = (hi - lo) * 0.5;
	float2 q = p - c;
	float r = q.y < 0 ? rt : rb;
	r = min(r, min(h.x, h.y));
	float2 d = abs(q) - h + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

[[ stitchable ]] half4 liquidGlass(
	float2 position, SwiftUI::Layer layer,
	float2 size, float inset, float topRadius, float bottomRadius, float openTop,
	float margin, float dark, float contrast, float lightBehind
) {
	float2 p = position - margin;
	float2 lo = float2(inset, openTop > 0.5 ? -400.0 : 0.0);
	float2 hi = float2(size.x - inset, size.y);
	float sd = roundedBox(p, lo, hi, topRadius, bottomRadius);

	// Outward normal from the distance field's gradient.
	const float e = 0.5;
	float2 grad = float2(
		roundedBox(p + float2(e, 0), lo, hi, topRadius, bottomRadius)
			- roundedBox(p - float2(e, 0), lo, hi, topRadius, bottomRadius),
		roundedBox(p + float2(0, e), lo, hi, topRadius, bottomRadius)
			- roundedBox(p - float2(0, e), lo, hi, topRadius, bottomRadius));
	float2 n = length(grad) > 1e-4 ? normalize(grad) : float2(0, -1);

	// The visible part's centre: for an attached panel, the strip below the screen edge.
	float2 visibleLo = float2(inset, 0);
	float2 centre = (visibleLo + hi) * 0.5;
	float2 halfSize = max((hi - visibleLo) * 0.5, float2(1));
	float side = min(hi.x - visibleLo.x, hi.y - visibleLo.y);

	// The lens. Depth from the rim, a band whose width follows the panel's size, and a
	// convex profile that is flat in the middle and steep at the edge.
	float depth = max(-sd, 0.0);
	float band = clamp(side * 0.34, 12.0, 22.0);
	float t = saturate(1.0 - depth / band);
	// Outside the box is the notch shape's flares, which the box does not model: no lens.
	float lens = pow(t, 1.6) * (1.0 - smoothstep(0.0, 3.0, sd));
	// The centre is very slightly magnified; the rim pulls in what lies just past the edge,
	// squeezed, so shapes crossing it visibly bend.
	float2 base = centre + (p - centre) / 1.03;
	// Plus a pull away from the centre, so lines crossing a straight side curve into it
	// rather than just sliding along it.
	// Kept under `margin` in total so the lens never samples past the crop.
	float2 bend = (n * band * 0.85 + (p - centre) / halfSize * 10.0) * lens;

	// Light frost, more in light mode, a little more over a busy light wallpaper.
	float frost = dark > 0.5 ? 1.2 : 2.6;
	float2 g = base + bend + margin;
	half4 col = layer.sample(g) * 0.28h;
	const float2 taps[6] = {
		float2(1, 0), float2(0.5, 0.866), float2(-0.5, 0.866),
		float2(-1, 0), float2(-0.5, -0.866), float2(0.5, -0.866) };
	for (int i = 0; i < 6; i++) {
		col += layer.sample(g + taps[i] * frost) * 0.12h;
	}

	// Dispersion: red bends a little less, blue a little more, only where the lens is.
	half4 green = layer.sample(g);
	float spread = 0.07 * lens;
	half red = layer.sample(base + bend * (1.0 - spread) - n * lens * 1.2 + margin).r;
	half blue = layer.sample(base + bend * (1.0 + spread) + n * lens * 1.2 + margin).b;
	col.r += (red - green.r) * 0.9h;
	col.b += (blue - green.b) * 0.9h;

	float3 rgb = float3(col.rgb);
	float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
	if (dark > 0.5) {
		// Glass over a dark picture reads a touch brighter and richer than the picture.
		rgb = mix(float3(luma), rgb, 1.25) * 1.1 + 0.035;
	} else {
		// Light glass is frostier: a white lift that still lets the picture through.
		rgb = mix(float3(luma), rgb, 1.2);
		rgb = mix(rgb, float3(1), 0.3);
	}

	// Readability behind the face mark and captions.
	float2 r = (p - centre) / halfSize;
	float spot = exp(-dot(r, r) * 1.1);
	if (dark > 0.5) {
		float dim = 0.16 + lightBehind * 0.16 + contrast * 0.18;
		rgb *= 1.0 - dim * (0.45 + 0.55 * spot);
	} else {
		float dim = 0.1 + lightBehind * 0.14 + contrast * 0.16;
		rgb = mix(rgb, float3(1), 0.12 * spot);
		rgb *= 1.0 - dim * (0.4 + 0.6 * spot);
	}

	// Thickness: a faint darker edge just inside the bottom.
	float lower = max(n.y, 0.0);
	rgb *= 1.0 - 0.16 * lower * exp(-max(depth - 1.5, 0.0) / 4.0) * smoothstep(0.0, 2.0, depth);

	// Soft light inside the top edge.
	float upper = max(-n.y, 0.0);
	rgb += 0.16 * upper * exp(-depth / 7.0) * (1.0 - openTop);

	// The specular rim: a hairline, brightest where the normal faces the light at the top
	// left, with a weaker catch on the opposite curve.
	float2 light = normalize(float2(-0.6, -0.8));
	float facing = dot(n, light);
	float fresnel = 0.32 + 0.9 * pow(max(facing, 0.0), 1.6) + 0.5 * pow(max(-facing, 0.0), 2.0);
	float width = 1.1 + contrast * 0.9;
	// Over a light picture a white rim alone disappears, so light glass gets a faint dark
	// outline at the very edge and its bright rim just inside it.
	float outline = dark > 0.5 ? 0.0 : 0.8;
	rgb *= 1.0 - (0.22 + contrast * 0.2) * (1.0 - smoothstep(0.0, outline + 0.01, depth))
		* (1.0 - smoothstep(0.0, 1.5, sd));
	float edge = max(depth - outline, 0.0);
	float hairline = (1.0 - smoothstep(width * 0.5, width + 0.6, edge)) * step(outline, depth);
	float glow = exp(-edge / 3.5) * 0.35;
	float onEdge = 1.0 - smoothstep(0.0, 1.5, sd);
	float rim = (hairline * (0.75 + contrast * 0.25) + glow) * fresnel * onEdge;
	if (openTop > 0.5) rim *= smoothstep(0.0, 6.0, p.y);
	rgb = rgb + (1.0 - rgb) * saturate(rim);

	return half4(half3(saturate(rgb)), 1.0h);
}

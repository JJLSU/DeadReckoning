shader_type canvas_item;
render_mode blend_disabled;
// Bakes one tree sprite (Tx._draw_tree, 128 x 128): soft overlapping blobs, each a radial
// gradient (light centre nudged to the upper left, the tree colour, then a darker edge fading
// out), painted in order like the original Pen.radial trees, plus fine grain on the leaves.
// Lit from the upper left; the game turns the sprite so that side faces the sun.
uniform vec4 blobs[28];   // x, y, radius (pixels), unused
uniform vec4 cols[28];    // the blob's colour (rgb 0..1)
uniform int count = 0;
uniform int seed = 1;

varying vec2 lp;

float hsh(int ix, int iy, int s) {
	uint h = uint(ix) * 374761393u + uint(iy) * 668265263u + uint(s) * 1442695041u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float vnoise(vec2 p, int s) {
	vec2 f0 = floor(p);
	ivec2 i = ivec2(f0);
	vec2 f = p - f0;
	f = f * f * (3.0 - 2.0 * f);
	float a = hsh(i.x, i.y, s), b = hsh(i.x + 1, i.y, s), c = hsh(i.x, i.y + 1, s), d = hsh(i.x + 1, i.y + 1, s);
	return a + (b - a) * f.x + (c - a) * f.y + (a - b - c + d) * f.x * f.y;
}

// leaf grain: clusters one to three pixels across, 0..1
float grain(vec2 p) {
	return vnoise(p / 1.1, seed + 3) * 0.55 + vnoise(p / 2.75, seed + 5) * 0.45;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 col = vec3(0.0);
	float acc = 0.0;
	for (int i = 0; i < 28; i++) {
		if (i >= count) break;
		vec2 c = blobs[i].xy;
		float r = blobs[i].z;
		vec3 base = cols[i].rgb;
		vec2 off = vec2(-0.35, -0.35) * r;
		float t0 = clamp(length(lp - c) / r, 0.0, 1.0);
		float d = length(lp - (c + off * (1.0 - t0))) / r;   // the highlight sits up and left
		if (d >= 1.0) continue;
		vec3 lite = base + vec3(40.0, 46.0, 20.0) / 255.0;
		vec3 dark = base - vec3(15.0, 20.0, 12.0) / 255.0;
		vec3 bc;
		float a = 1.0;
		if (d < 0.72) bc = mix(lite, base, smoothstep(2.0 / r, 0.72, d));
		else { float k = (d - 0.72) / 0.28; bc = mix(base, dark, k); a = 1.0 - k; }
		col = mix(col, bc, a);
		acc = a + acc * (1.0 - a);
	}
	// fine grain: leaf clusters with a little relief lit from the upper left, plus speckle
	float n0 = grain(lp);
	float n1 = grain(lp + vec2(-0.65, -0.65));
	float relief = (n1 - n0) * 1.6;
	float speck = hsh(int(lp.x), int(lp.y), seed + 9) - 0.5;
	col *= 1.0 - relief * 0.35 + speck * 0.08 + (n0 - 0.5) * 0.18;
	// ragged leafy rim instead of a perfectly smooth fade
	acc = clamp(acc * (0.75 + n0 * 0.5), 0.0, 1.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), acc);
}

shader_type canvas_item;
// Trees and bushes in the flight view (render.gd, scatter chunks). Their instances never
// change; the lean with height and the sun shadow are applied here from per-frame uniforms.
// INSTANCE_CUSTOM = (centre x, centre y, height, r): r > 0 canopy, r < 0 shadow, with |r| =
// height / quad size. Everything else drawn on the same layer has r = 0 and passes through.
// One more instance kind, custom = (centre x, centre y, -1, 0), is the mist and haze pass: a
// quad over the whole view whose colour is worked out per pixel in fragment() (render.gd
// draw_fog). It goes over the ground, trees and buildings and under the plane.
// And custom = (centre x, centre y, -2, 0) is a terrain chunk: its texture gets fine detail
// (grain, clumps and a little relief lit by the sun) that fades in near the ground.
// custom = (0, 0, -3, 0) is the Failsafe farm (failsafe.gd): each pixel traces the line of
// sight through the farm's height map, then lights what it finds with the sun.
uniform vec2 cam;          // camera centre, world units
uniform float eye = 1000.0; // camera height above the ground, world units
uniform vec2 trot = vec2(1.0, 0.0);    // cos/sin turn so the sprite's lit side faces the sun
uniform vec2 sun = vec2(0.3, 0.5);     // shadow offset per unit of height
uniform vec2 sun_dir = vec2(1.0, 0.0); // unit vector along the shadows
uniform float sun_len = 1.0;
uniform float fade = 1.0;  // tree and shadow alpha (render.gd tree_fade: follows altitude in flight)
uniform float mist_fade = 1.0; // forest mist alpha, fades in with the view scale
uniform float sun_a = 1.0; // shadow strength
uniform float canopy_a = 1.0; // canopy opacity: crowns stay a little see-through so the layers blend
uniform float canopy_core = 1.667; // each crown's opacity is scaled by this at its middle (70% on the ground)...
uniform float canopy_rim = 0.8;   // ...blending to this toward its rim
uniform float canopy_sat = 1.4;    // crowns are more saturated and brighter, since they are drawn
uniform float canopy_bright = 1.35; // see-through over the dark forest floor (Greg, 2026-10-14)

uniform int seed = 1;
uniform float world_size = 60000.0;
uniform vec2 fog_size = vec2(1000.0);   // view size, world units
uniform float tsec = 0.0;               // seconds, for the drift
uniform vec2 drift = vec2(4.0, 1.5);    // mist drift, world units per second
uniform float mist = 0.0;               // 0..1, how much mist lies in the low ground right now
uniform vec3 mist_col : source_color = vec3(0.92, 0.93, 0.94);
uniform float mist_h = 30.0;            // mist top height, for its parallax
uniform float haze = 0.0;               // 0..1, height haze strength
uniform vec3 haze_col : source_color = vec3(0.7, 0.77, 0.86);

uniform float detail = 0.0;             // 0..1, terrain detail strength (rises near the ground)
uniform float chunk_w = 1025.0;         // terrain chunk quad size, world units
uniform float fmist = 0.0;              // 0..1, forest mist lying under the treetops
uniform float t3_a = 1.0;               // opacity of the 3D-rendered test trees (render.gd T3D)

// Failsafe farm (failsafe.gd). Lengths in world units, in the farm's own frame.
uniform sampler2D farm_col : filter_linear_mipmap, repeat_disable;   // seen from above, even sky light
uniform sampler2D farm_hgt : filter_linear, repeat_disable;          // height, 0..1 of farm_h
uniform sampler2D farm_wall : filter_linear_mipmap, repeat_disable;  // walls from 8 sides, 4 x 2
uniform vec2 farm_size = vec2(267.0, 207.0);
uniform vec2 farm_q = vec2(300.0);      // quad size
uniform vec2 farm_cam;                  // camera
uniform vec2 farm_sun = vec2(0.3, 0.5); // shadow offset per unit of height
uniform float farm_h = 48.0;            // top of the height map
uniform float farm_shear = 0.7;         // wall views: sideways shift per unit of height
uniform float farm_gain = 1.0;
uniform float farm_sat = 1.0;
uniform sampler2D farm_shd : filter_linear, repeat_disable;   // sun shadows on the farm's surface (farm_shadow.gdshader)
uniform vec4 farm_shd_area = vec4(0.0, 0.0, 1.0, 1.0);        // what farm_shd covers: corner xy, size zw
uniform float farm_shd_ok = 0.0;                               // 1 once farm_shd has been made

varying vec2 wpos;
varying float fogm;

// Same noise as terrain.gdshader, so the mist follows the land's low ground.
float hsh(int ix, int iy, int s) {
	uint h = uint(ix) * 374761393u + uint(iy) * 668265263u + uint(s) * 1442695041u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float vnoise(float x, float y, int s) {
	float fx0 = floor(x), fy0 = floor(y);
	int ix = int(fx0), iy = int(fy0);
	float fx = x - fx0, fy = y - fy0;
	fx = fx * fx * (3.0 - 2.0 * fx);
	fy = fy * fy * (3.0 - 2.0 * fy);
	float a = hsh(ix, iy, s), b = hsh(ix + 1, iy, s), c = hsh(ix, iy + 1, s), d = hsh(ix + 1, iy + 1, s);
	return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
}

float fbm(float x, float y, int s, int o) {
	float v = 0.0, amp = 0.5, f = 1.0, n = 0.0;
	for (int i = 0; i < o; i++) {
		v += vnoise(x * f, y * f, s + i * 31) * amp;
		n += amp; amp *= 0.5; f *= 2.03;
	}
	return v / n;
}

// Mist in the low ground (rivers, lakes, coasts, valleys), drifting with the wind, plus a haze
// that thickens towards the edges of the view (further from the eye) as you climb.
vec4 fog_at(vec2 p) {
	vec2 d = (p - cam) / (fog_size * 0.5);
	float hz = haze * (0.4 + 0.6 * clamp(dot(d, d) * 0.5, 0.0, 1.0));
	float m = 0.0;
	if (mist > 0.001) {
		vec2 q = cam + (p - cam) * (eye - mist_h) / eye;
		float e = fbm(q.x / 6500.0, q.y / 6500.0, seed, 4);
		float edge = min(min(q.x, q.y), min(world_size - q.x, world_size - q.y));
		if (edge < 1800.0) e -= (1800.0 - edge) / 1800.0 * 0.25;
		float low = (1.0 - smoothstep(0.42, 0.54, e)) * smoothstep(0.27, 0.35, e);
		vec2 w = q - drift * tsec;
		// streaks stretched along the wind
		vec2 u = normalize(drift + vec2(0.0001, 0.0));
		vec2 sw = vec2(dot(w, u) / 2.2, dot(w, vec2(-u.y, u.x)));
		float n = (fbm(sw.x / 380.0, sw.y / 380.0, seed + 501, 4) - 0.5) * 2.4 + 0.5;
		n += (vnoise(w.x / 90.0, w.y / 90.0, seed + 507) - 0.5) * 0.16;
		float cover = low * mist;
		float t = 1.05 - cover * 0.85;
		m = smoothstep(t - 0.25, t + 0.2, n) * min(cover * 3.0, 1.0) * 0.66;
	}
	float a = 1.0 - (1.0 - m) * (1.0 - hz);
	vec3 c = mix(haze_col, mist_col, m / max(m + hz, 0.0001));
	return vec4(c, a);
}

// Fine ground detail over a terrain chunk texel colour c at world point p.
vec3 detail_at(vec3 c, vec2 p) {
	float green = clamp((c.g - max(c.r, c.b)) * 9.0 + 0.2, 0.0, 1.0);
	float water = clamp((c.b - c.r) * 7.0, 0.0, 1.0);
	float n0 = vnoise(p.x / 2.4, p.y / 2.4, seed + 601) * 0.55 + vnoise(p.x / 7.5, p.y / 7.5, seed + 603) * 0.45;
	vec2 q = p + sun_dir * 1.8;
	float n1 = vnoise(q.x / 2.4, q.y / 2.4, seed + 601) * 0.55 + vnoise(q.x / 7.5, q.y / 7.5, seed + 603) * 0.45;
	float relief = (n1 - n0) * sun_a;
	float speck = vnoise(p.x / 0.9, p.y / 0.9, seed + 607) - 0.5;
	float clump = vnoise(p.x / 14.0, p.y / 14.0, seed + 609) - 0.5;
	float k = 1.0 + relief * (0.36 + 0.3 * green) + speck * 0.06 + clump * 0.16 * green;
	vec3 d = c * k;
	d.r += clump * 0.025 * green;   // drier and lusher patches in the grass
	return mix(c, d, detail * (1.0 - water));
}

float farm_ht(vec2 q) {
	vec2 uv = q / farm_size + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return textureLod(farm_hgt, uv, 0.0).r * farm_h;
}

// The ground point whose height-h top shows at p (render.gd lift(), backwards).
vec2 farm_back(vec2 p, float h) {
	return farm_cam + (p - farm_cam) / (1.0 + h / max(eye - h, eye * 0.25));
}

vec4 farm_at(vec2 p) {
	vec2 g0 = dFdx(p) / farm_size;
	vec2 g1 = dFdy(p) / farm_size;
	// nothing to draw where neither the line of sight nor the sun's ray can reach the farm
	vec2 top = farm_back(p, farm_h);
	vec2 sp = p - farm_sun * farm_h;
	vec2 bmin = min(min(top, p), sp);
	vec2 bmax = max(max(top, p), sp);
	vec2 fh = farm_size * 0.5;
	if (bmax.x < -fh.x || bmax.y < -fh.y || bmin.x > fh.x || bmin.y > fh.y) return vec4(0.0);
	// walk the line of sight down from the top of the height map until it goes under the surface,
	// in steps of about 1.5 units of lean (few near the middle of the view, where tops barely lean)
	int N = clamp(int(length(p - top) / 1.5), 4, 48);
	float hp = farm_h;
	float dp = farm_h - farm_ht(farm_back(p, farm_h));
	float hc = 0.0;
	float dc = 0.0;
	for (int i = 1; i <= N; i++) {
		hc = farm_h * (1.0 - float(i) / float(N));
		dc = hc - farm_ht(farm_back(p, hc));
		if (dc <= 0.0) break;
		hp = hc;
		dp = dc;
	}
	float lo = hc, hi = hp;
	for (int i = 0; i < 5; i++) {
		float m = 0.5 * (lo + hi);
		if (m - farm_ht(farm_back(p, m)) <= 0.0) lo = m; else hi = m;
	}
	float h = 0.5 * (lo + hi);
	vec2 q = farm_back(p, h);
	vec2 uv = q / farm_size + 0.5;
	vec2 ld = normalize(p - farm_cam + vec2(0.0001, 0.0));   // the way tops lean, away from the eye
	// a wall when the surface keeps rising just beyond the hit, into the building
	bool wall = farm_ht(q + ld * 1.5) - h > 2.0;
	vec4 c;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	vec3 l = normalize(vec3(-farm_sun, 1.0));
	if (wall) {
		// walls: from the two side views nearest this line of sight
		float a = atan(ld.y, ld.x) / 0.785398;
		a = mod(a + 8.0, 8.0);
		int j0 = int(floor(a)) % 8;
		int j1 = (j0 + 1) % 8;
		float f = fract(a);
		vec4 cs[2];
		for (int k = 0; k < 2; k++) {
			int j = k == 0 ? j0 : j1;
			float th = float(j) * 0.785398;
			vec2 w = (q + vec2(cos(th), sin(th)) * farm_shear * h) / farm_size + 0.5;
			w = clamp(w, vec2(0.002), vec2(0.998));
			vec2 au = (vec2(float(j % 4), float(j / 4)) + w) / vec2(4.0, 2.0);
			cs[k] = textureGrad(farm_wall, au, g0 / vec2(4.0, 2.0), g1 / vec2(4.0, 2.0));
		}
		c = mix(cs[0], cs[1], f);
		nrm = vec3(-ld, 0.0);
	} else {
		c = textureGrad(farm_col, uv, g0, g1);
		float e = farm_size.x / float(textureSize(farm_hgt, 0).x);
		float hx = farm_ht(q + vec2(e, 0.0)) - farm_ht(q - vec2(e, 0.0));
		float hy = farm_ht(q + vec2(0.0, e)) - farm_ht(q - vec2(0.0, e));
		if (abs(hx) < 3.0 * e && abs(hy) < 3.0 * e) nrm = normalize(vec3(-hx, -hy, 2.0 * e));
	}
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) c.a = 0.0;
	// sun: slopes and walls turned to it are brighter, then shadows from the height map
	float lit = 1.0 + 0.7 * (dot(nrm, l) - (wall ? 0.0 : l.z));
	lit = mix(1.0, clamp(lit, 0.6, 1.3), sun_a);
	float sh = 0.0;
	vec2 su = (q - farm_shd_area.xy) / farm_shd_area.zw;
	if (sun_a > 0.01 && !wall && farm_shd_ok > 0.5) {
		// roofs and ground: read the shadows made once for this sun (Failsafe._bake_shadow)
		if (su.x >= 0.0 && su.y >= 0.0 && su.x <= 1.0 && su.y <= 1.0) sh = textureLod(farm_shd, su, 0.0).r;
	} else if (sun_a > 0.01) {
		// walls (and before that texture exists): march toward the sun here
		// step about 2 units along the ground so thin things (poles, silos) still cast whole shadows
		float top = farm_h - h;
		int n = clamp(int(length(farm_sun) * top / 2.0), 8, 64);
		float t0 = wall ? 3.0 : 0.6;
		for (int i = 1; i <= n && sh == 0.0; i++) {
			float t = t0 + top * float(i) / float(n);
			if (farm_ht(q - farm_sun * t) > h + t + 0.3) sh = 1.0;
		}
	}
	float sa = 0.5 * sun_a * sh; if (farm_gain > 5.0) return vec4(sh, h / farm_h, wall ? 1.0 : 0.0, 1.0);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(vec3(lum), c.rgb, farm_sat) * farm_gain * lit * (1.0 - sa);
	float a = c.a + sa * (1.0 - c.a);
	return vec4(rgb * c.a / max(a, 0.001), a);
}

void vertex() {
	float r = INSTANCE_CUSTOM.w;
	fogm = 0.0;
	if (r > 200.0 && r < 400.0) {   // 3D-rendered tree layer: leans like a canopy, solid, own colours
		vec2 v = VERTEX;
		float k = (r - 300.0) / max(eye - INSTANCE_CUSTOM.z, eye * 0.25);
		VERTEX = vec2(v.x * trot.x - v.y * trot.y, v.x * trot.y + v.y * trot.x) + (INSTANCE_CUSTOM.xy - cam) * k;
		COLOR.a *= t3_a;
	} else if (r < -200.0 && r > -400.0) {   // 3D-rendered tree shadow: its silhouette along the sun
		float q = -(r + 300.0);
		vec2 v = VERTEX;
		v.x *= 1.0 + sun_len * q * 0.65;
		VERTEX = vec2(v.x * sun_dir.x - v.y * sun_dir.y, v.x * sun_dir.y + v.y * sun_dir.x) + sun * q * 0.675;
		COLOR.a *= t3_a * sun_a;
	} else if (r > 500.0) {   // forest mist puff: leans like a canopy at its height, mist coloured
		vec2 v = VERTEX;
		float k = (r - 1000.0) / max(eye - INSTANCE_CUSTOM.z, eye * 0.25);
		VERTEX = v + (INSTANCE_CUSTOM.xy - cam) * k;
		COLOR = vec4(mist_col, fmist * 0.5 * mist_fade);
	} else if (r == 0.0 && INSTANCE_CUSTOM.z < -2.5) {
		fogm = 4.0;
		wpos = VERTEX * farm_q;
	} else if (r == 0.0 && INSTANCE_CUSTOM.z < -1.5) {
		fogm = 2.0;
		wpos = INSTANCE_CUSTOM.xy + VERTEX * chunk_w;
	} else if (r == 0.0 && INSTANCE_CUSTOM.z < 0.0) {
		fogm = 1.0;
		wpos = INSTANCE_CUSTOM.xy + VERTEX * fog_size;
	} else if (r > 0.0) {
		vec2 v = VERTEX;
		float k = r / max(eye - INSTANCE_CUSTOM.z, eye * 0.25);
		VERTEX = vec2(v.x * trot.x - v.y * trot.y, v.x * trot.y + v.y * trot.x) + (INSTANCE_CUSTOM.xy - cam) * k;
		COLOR.a *= min(fade, canopy_a) * 2.0;   // instance alpha is opacity / 2 (render.gd EDGE_OPACITY)
		fogm = 3.0;   // fragment() blends the crown from a denser middle to a lighter rim
	} else if (r < 0.0) {
		float q = -r;
		vec2 v = VERTEX;
		v.x *= 1.0 + sun_len * q * 0.65;
		VERTEX = vec2(v.x * sun_dir.x - v.y * sun_dir.y, v.x * sun_dir.y + v.y * sun_dir.x) + sun * q * 0.675;
		COLOR.a *= fade * sun_a;
	}
}

void fragment() {
	if (fogm > 3.5) COLOR = farm_at(wpos);
	else if (fogm > 2.5) {
		COLOR.a = min(1.0, COLOR.a * mix(canopy_core, canopy_rim, smoothstep(0.0, 0.9, length(UV - 0.5) * 2.0)));
		float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR.rgb = clamp(mix(vec3(lum), COLOR.rgb, canopy_sat) * canopy_bright, 0.0, 1.0);
	}
	else if (fogm > 1.5) COLOR.rgb = detail_at(COLOR.rgb, wpos);
	else if (fogm > 0.5) COLOR = fog_at(wpos);
}

shader_type canvas_item;
// GPU port of terr() + col() from the HTML version. Renders one terrain chunk (or the
// whole-world overview) into a SubViewport; the result is read back into a texture.

uniform int seed = 1;
uniform vec2 haven = vec2(0.0);
uniform int road_count = 0;
uniform vec4 road_p[16];
uniform vec2 origin = vec2(0.0);
uniform float step_u = 4.0;
uniform float grid = 256.0;
uniform bool shade_on = true;

const float WORLD = 30000.0;

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

int terr(float x, float y, out float TE, out float TM) {
	TM = 0.5;
	if (x < 0.0 || y < 0.0 || x > WORLD || y > WORLD) { TE = 0.3; return 0; }
	float dh = distance(vec2(x, y), haven);
	float e = fbm(x / 6500.0, y / 6500.0, seed, 5);
	float edge = min(min(x, y), min(WORLD - x, WORLD - y));
	if (edge < 1800.0) e -= (1800.0 - edge) / 1800.0 * 0.25;
	if (dh < 1700.0) e = max(e, 0.47);
	TE = e;
	if (e >= 0.36) {
		for (int i = 0; i < 16; i++) {
			if (i >= road_count) break;
			vec4 r = road_p[i];
			if (x < min(r.x, r.z) - 22.0 || x > max(r.x, r.z) + 22.0 || y < min(r.y, r.w) - 22.0 || y > max(r.y, r.w) + 22.0) continue;
			float dx = r.z - r.x, dy = r.w - r.y, len2 = dx * dx + dy * dy, len = sqrt(len2);
			float tt = clamp(((x - r.x) * dx + (y - r.y) * dy) / len2, 0.0, 1.0);
			float ex = r.x + dx * tt - x, ey = r.y + dy * tt - y, d2 = ex * ex + ey * ey;
			if (d2 < 400.0) return (d2 < 9.0 && (int(floor(tt * len / 40.0)) & 1) == 1) ? 12 : 11;
			if (d2 < 800.0) return 13;
		}
	}
	if (e < 0.36) return 0;
	if (e < 0.40) return 1;
	float rv = abs(fbm(x / 8000.0 + 17.3, y / 8000.0 + 3.1, seed + 99, 3) - 0.5);
	if (rv < 0.009 && e < 0.62 && dh > 1700.0) return 1;
	if (rv < 0.0125 && e < 0.62 && dh > 1700.0) return 14;
	if (e < 0.408) return 2;
	if (e > 0.70) return e > 0.75 ? 8 : 7;
	if (dh > 1700.0) {
		float tn = vnoise(x / 2200.0 + 5.0, y / 2200.0 + 5.0, seed + 55);
		if (tn > 0.86 && e < 0.62) {
			int gx = int(floor(x / 70.0)), gy = int(floor(y / 70.0));
			return (gx % 4 == 0 || gy % 4 == 0) ? 10 : 9;
		}
	}
	float m = fbm(x / 4500.0 + 40.0, y / 4500.0 + 40.0, seed + 7, 4);
	TM = m;
	if (m > 0.62) return 6;
	if (m > 0.53) return 5;
	if (m < 0.43) return 4;
	return 3;
}

vec3 fieldc(int i) {
	if (i == 0) return vec3(118.0, 112.0, 66.0);
	if (i == 1) return vec3(134.0, 122.0, 72.0);
	if (i == 2) return vec3(98.0, 110.0, 58.0);
	if (i == 3) return vec3(142.0, 128.0, 86.0);
	return vec3(110.0, 96.0, 60.0);
}
vec3 roofc(int i) {
	if (i == 0) return vec3(112.0, 70.0, 52.0);
	if (i == 1) return vec3(96.0, 88.0, 82.0);
	if (i == 2) return vec3(70.0, 62.0, 58.0);
	if (i == 3) return vec3(128.0, 112.0, 92.0);
	return vec3(40.0, 36.0, 34.0);
}

vec3 colr(int t, float x, float y, float e, float sh) {
	vec3 c;
	if (t <= 1) {
		float k = clamp((e - 0.28) / 0.12, 0.0, 1.0);
		c = vec3(22.0 + k * 30.0, 42.0 + k * 44.0, 56.0 + k * 40.0);
		float wv = sin((x * 0.7 + y * 0.3) / 34.0 + vnoise(x / 300.0, y / 300.0, seed + 87) * 6.0) * 3.0 * (1.0 - k * 0.5);
		c += vec3(wv);
		if (t == 1 && e > 0.4) c = vec3(46.0, 80.0, 92.0);
		if (e > 0.389 && e < 0.40) c += vec3(24.0, 24.0, 20.0);
		c += vec3(vnoise(x / 60.0, y / 60.0, seed + 3) * 8.0);
		sh = 0.0;
	} else if (t == 2) {
		c = vec3(148.0, 138.0, 104.0);
	} else if (t == 3 || t == 5 || t == 6) {
		float tn = vnoise(x / 900.0, y / 900.0, seed + 31);
		if (t == 3) {
			float f2 = (vnoise(x / 18.0, y / 18.0, seed + 37) - 0.5) * 14.0;
			c = vec3(78.0 + tn * 20.0 + f2, 98.0 + tn * 14.0 + f2, 52.0 + tn * 6.0 + f2 * 0.4);
		} else {
			vec3 base = t == 5 ? vec3(62.0, 84.0, 46.0) : vec3(44.0, 62.0, 36.0);
			float k = (vnoise(x / 46.0, y / 46.0, seed + 23) - 0.5) * 0.75 + (vnoise(x / 15.0, y / 15.0, seed + 29) - 0.5) * 0.32 + (tn - 0.5) * 0.15;
			c = base * (1.0 + k);
			float au = vnoise(x / 650.0, y / 650.0, seed + 131);
			if (au > 0.58) {
				float a = clamp((au - 0.58) / 0.12, 0.0, 1.0) * 0.72;
				float pk = hsh(int(floor(x / 56.0)), int(floor(y / 56.0)), seed + 133);
				vec3 cc = pk < 0.33 ? vec3(128.0, 78.0, 36.0) : (pk < 0.66 ? vec3(146.0, 118.0, 46.0) : vec3(112.0, 52.0, 34.0));
				c = mix(c, cc * (1.0 + k), a);
			}
		}
	} else if (t == 4) {
		float wx = x + (vnoise(x / 700.0, y / 700.0, seed + 41) - 0.5) * 360.0;
		float wy = y + (vnoise(x / 700.0 + 9.0, y / 700.0 + 9.0, seed + 43) - 0.5) * 360.0;
		int cx = int(floor(wx / 420.0)), cy = int(floor(wy / 300.0));
		float h = hsh(cx, cy, seed + 17);
		c = fieldc(int(h * 5.0));
		float lx = wx - float(cx) * 420.0, ly = wy - float(cy) * 300.0;
		if (lx < 10.0 || ly < 10.0) c = vec3(66.0, 82.0, 44.0);
		else if ((int(floor((h < 0.5 ? lx : ly) / 22.0)) & 1) == 1) c += vec3(10.0, 9.0, 4.0);
		if (hsh(cx, cy, seed + 19) < 0.24 && lx > 28.0 && lx < 172.0 && ly > 28.0 && ly < 100.0) {
			c = vec3(118.0, 106.0, 80.0);
			vec3 rc = roofc(int(hsh(cx, cy, seed + 21) * 5.0));
			if (lx > 44.0 && lx < 82.0 && ly > 40.0 && ly < 70.0) { c = rc; if (ly > 55.0) c *= 0.72; }
			else if (lx > 82.0 && lx < 88.0 && ly > 44.0 && ly < 74.0) c = vec3(70.0, 64.0, 54.0);
			else if (lx > 100.0 && lx < 152.0 && ly > 44.0 && ly < 88.0) { c = vec3(124.0, 48.0, 36.0); if (lx > 126.0) c *= 0.72; }
			else if (lx > 152.0 && lx < 158.0 && ly > 48.0 && ly < 92.0) c = vec3(70.0, 60.0, 50.0);
		}
	} else if (t == 7) {
		float q = (vnoise(x / 38.0, y / 38.0, seed + 61) - 0.5) * 34.0 + (vnoise(x / 11.0, y / 11.0, seed + 63) - 0.5) * 14.0;
		c = vec3(110.0 + q, 104.0 + q, 94.0 + q * 0.9);
	} else if (t == 8) {
		c = vec3(198.0, 198.0, 192.0);
	} else if (t == 9) {
		int bx = int(floor(x / 70.0)), by = int(floor(y / 70.0));
		float h = hsh(bx, by, seed + 9);
		float lx = x - float(bx) * 70.0, ly = y - float(by) * 70.0;
		float x0 = 6.0 + hsh(bx, by, seed + 11) * 12.0, x1 = 46.0 + hsh(bx, by, seed + 12) * 16.0;
		float y0 = 6.0 + hsh(bx, by, seed + 13) * 12.0, y1 = 46.0 + hsh(bx, by, seed + 14) * 16.0;
		if (lx < x0 || lx > x1 || ly < y0 || ly > y1) {
			c = h < 0.3 ? vec3(74.0, 72.0, 68.0) : vec3(84.0, 92.0, 62.0);
			if ((lx > x1 && lx < x1 + 7.0 && ly > y0 + 4.0 && ly < y1 + 7.0) || (ly > y1 && ly < y1 + 7.0 && lx > x0 + 4.0 && lx < x1 + 7.0)) c *= 0.62;
		} else {
			c = roofc(int(h * 5.0));
			if (h < 0.12) c = vec3(34.0, 30.0, 28.0);
			float mid = (x1 - x0) > (y1 - y0) ? (ly - y0) / (y1 - y0) : (lx - x0) / (x1 - x0);
			if (mid > 0.5) c *= 0.74;
		}
	} else if (t == 10) c = vec3(70.0, 68.0, 64.0);
	else if (t == 11) c = vec3(60.0, 58.0, 56.0);
	else if (t == 13) c = vec3(104.0, 96.0, 80.0);
	else if (t == 14) c = vec3(90.0, 86.0, 64.0);
	else c = vec3(182.0, 156.0, 66.0);
	if (t >= 3 && t <= 6) {
		float dry = clamp((e - 0.5) / 0.18, 0.0, 1.0);
		c += vec3(dry * 18.0, -dry * 5.0, -dry * 4.0);
	}
	if ((t >= 3 && t <= 6) || t == 9) {
		float bn = vnoise(x / 1900.0, y / 1900.0, seed + 81);
		if (bn > 0.78) {
			float k = clamp((bn - 0.78) / 0.07, 0.0, 1.0) * 0.88;
			float q = (vnoise(x / 30.0, y / 30.0, seed + 83) - 0.5) * 24.0;
			c = mix(c, vec3(46.0 + q, 43.0 + q, 40.0 + q * 0.8), k);
		}
	}
	float j = (hsh(int(x) >> 3, int(y) >> 3, seed + 5) - 0.5) * 9.0;
	float L = 1.0 + sh + (t >= 2 ? (e - 0.5) * 0.35 : 0.0);
	return (c + vec3(j)) * L;
}

void fragment() {
	vec2 px = floor(UV * grid);
	vec2 w = origin + px * step_u + vec2(step_u * 0.5);
	float te, tm;
	int t = terr(w.x, w.y, te, tm);
	float sh = 0.0;
	if (shade_on && t >= 2) {
		float pe, pm;
		terr(w.x - step_u, w.y - step_u, pe, pm);
		sh = clamp((pe - te) * 95.0, -0.36, 0.36);
	}
	vec3 c = colr(t, w.x, w.y, te, sh);
	COLOR = vec4(clamp(c / 255.0, 0.0, 1.0), 1.0);
}

shader_type canvas_item;
// GPU port of terr() + col() from the HTML version. Renders one terrain chunk (or the
// whole-world overview) into a SubViewport; the result is read back into a texture.

uniform int seed = 1;
uniform vec2 haven = vec2(0.0);
uniform int road_count = 0;
uniform vec4 road_p[64];
uniform vec2 origin = vec2(0.0);
uniform float step_u = 4.0;
uniform float grid = 256.0;
uniform bool shade_on = true;
uniform int gen = 2;   // World.GEN: 3 adds bridges, tapered road ends and towns that thin out

uniform float WORLD = 60000.0;   // land size, set from D.WORLD by baker.gd

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

// Ocean outside the land square: open water with the odd small island
// (mirrors World.isle() in world.gd - keep the numbers in sync).
const float ISLE_SCALE = 1800.0;
const float ISLE_T = 0.76;
const float ISLE_K = 3.2;
const float ISLE_GAP = 3000.0;
int isle(float x, float y, out float TE, out float TM) {
	TM = 0.5;
	float f = fbm(x / ISLE_SCALE, y / ISLE_SCALE, seed + 311, 4);
	float dout = max(max(-x, x - WORLD), max(-y, y - WORLD));
	if (dout < ISLE_GAP) f -= (ISLE_GAP - dout) / ISLE_GAP * 0.2;
	float e = max(0.3, 0.36 + (f - ISLE_T) * ISLE_K);
	TE = e;
	if (e < 0.36) return 0;
	if (e < 0.40) return 1;
	if (e < 0.408) return 2;
	if (e > 0.70) return e > 0.75 ? 8 : 7;
	float m = fbm(x / 4500.0 + 40.0, y / 4500.0 + 40.0, seed + 7, 4);
	TM = m;
	if (m > 0.62) return 6;
	if (m > 0.53) return 5;
	if (m < 0.43) return 4;
	return 3;
}

int terr(float x, float y, out float TE, out float TM) {
	TM = 0.5;
	if (x < 0.0 || y < 0.0 || x > WORLD || y > WORLD) return isle(x, y, TE, TM);
	float dh = distance(vec2(x, y), haven);
	float e = fbm(x / 6500.0, y / 6500.0, seed, 5);
	float edge = min(min(x, y), min(WORLD - x, WORLD - y));
	if (edge < 1800.0) e -= (1800.0 - edge) / 1800.0 * 0.25;
	if (dh < 1700.0) e = max(e, 0.47);
	TE = e;
	if (e >= 0.36 || gen >= 3) {   // gen 3 roads carry on over water as bridges
		for (int i = 0; i < 64; i++) {
			if (i >= road_count) break;
			vec4 r = road_p[i];
			if (x < min(r.x, r.z) - 22.0 || x > max(r.x, r.z) + 22.0 || y < min(r.y, r.w) - 22.0 || y > max(r.y, r.w) + 22.0) continue;
			float dx = r.z - r.x, dy = r.w - r.y, len2 = dx * dx + dy * dy, len = sqrt(len2);
			float tt = clamp(((x - r.x) * dx + (y - r.y) * dy) / len2, 0.0, 1.0);
			float ex = r.x + dx * tt - x, ey = r.y + dy * tt - y, d2 = ex * ex + ey * ey;
			if (gen >= 3) {
				float de = min(tt, 1.0 - tt) * len;
				if (de < 380.0) {   // the road peters out into a dirt track that fades away
					if (d2 < 36.0 && hsh(int(x) >> 3, int(y) >> 3, seed + 65) < de / 60.0) return 13;
					continue;
				}
				if (de < 540.0) {   // and narrows before it gets there
					float k = 0.4 + 0.6 * (de - 380.0) / 160.0;
					d2 /= k * k;
				}
			}
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
	if (dh > 1700.0 && gen < 4) {   // gen 4: no painted town blocks
		float tn = vnoise(x / 2200.0 + 5.0, y / 2200.0 + 5.0, seed + 55);
		if (tn > (gen >= 3 ? 0.8 : 0.86) && e < 0.62) {
			int gx = int(floor(x / 70.0)), gy = int(floor(y / 70.0));
			bool street = gx % 4 == 0 || gy % 4 == 0;
			if (gen < 3) return street ? 10 : 9;
			// gen 3: blocks thin out toward the edge, down to the odd house on open ground
			float p = smoothstep(0.82, 0.88, tn + (vnoise(x / 600.0, y / 600.0, seed + 57) - 0.5) * 0.04) * smoothstep(0.62, 0.58, e);
			if (street) {
				if (p > 0.3 + hsh(int(floor(float(gx) / 4.0)), int(floor(float(gy) / 4.0)), seed + 59) * 0.4) return 10;
			} else if (hsh(gx, gy, seed + 61) < p) return 9;
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
			// forest floor in deep shade under a closed canopy, so gaps between crowns read dark
			vec3 base = t == 5 ? vec3(10.0, 14.0, 8.0) : vec3(6.0, 9.0, 5.0);
			float k = (vnoise(x / 46.0, y / 46.0, seed + 23) - 0.5) * 0.75 + (vnoise(x / 15.0, y / 15.0, seed + 29) - 0.5) * 0.32 + (tn - 0.5) * 0.15;
			c = base * (1.0 + k) * (0.75 + vnoise(x / 7.0, y / 7.0, seed + 27) * 0.5);
			float au = vnoise(x / 650.0, y / 650.0, seed + 131);
			if (au > 0.58) {
				float a = clamp((au - 0.58) / 0.12, 0.0, 1.0) * 0.72;
				float pk = vnoise(x / 70.0, y / 70.0, seed + 133);   // fallen leaves, smooth under the canopy
				vec3 cc = pk < 0.33 ? vec3(128.0, 78.0, 36.0) : (pk < 0.66 ? vec3(146.0, 118.0, 46.0) : vec3(112.0, 52.0, 34.0));
				c = mix(c, cc * (t == 5 ? 0.13 : 0.1) * (1.0 + k), a);
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

// Soft, ragged edges between natural ground types. Only the colour changes: terr() and
// the CPU copy of it keep their hard thresholds, so gameplay sees the same ground.
float edge_jit(float x, float y) {
	return (vnoise(x / 90.0, y / 90.0, seed + 141) - 0.5) * 0.02 + (vnoise(x / 23.0, y / 23.0, seed + 143) - 0.5) * 0.003;
}
int low_type(float m) {
	if (m > 0.62) return 6;
	if (m > 0.53) return 5;
	if (m < 0.43) return 4;
	return 3;
}
vec3 blend_biomes(int t, vec3 c, float x, float y, float e, float sh) {
	float j = edge_jit(x, y);
	// farmland follows whole fields: a field near the edge is either all crop or all grass
	if (t == 3 || t == 4) {
		float wx = x + (vnoise(x / 700.0, y / 700.0, seed + 41) - 0.5) * 360.0;
		float wy = y + (vnoise(x / 700.0 + 9.0, y / 700.0 + 9.0, seed + 43) - 0.5) * 360.0;
		float cx = floor(wx / 420.0), cy = floor(wy / 300.0);
		float mc = fbm(((cx + 0.5) * 420.0) / 4500.0 + 40.0, ((cy + 0.5) * 300.0) / 4500.0 + 40.0, seed + 7, 4);
		mc += (hsh(int(cx), int(cy), seed + 25) - 0.5) * 0.03;
		bool farm = mc < 0.43;
		if (t == 3 && farm) c = colr(4, x, y, e, sh);
		else if (t == 4 && !farm) c = colr(3, x, y, e, sh);
	}
	// beaches fade into the grass behind them
	if (e < 0.43 && t <= 6) {
		float k = 1.0 - smoothstep(0.401, 0.416, e + j * 0.3);
		c = mix(c, colr(2, x, y, e, sh), k);
	}
	// rock and snow feather out over the hills instead of a cut line
	if (e > 0.665) {
		vec3 low = c;
		if (t >= 7) low = colr(low_type(fbm(x / 4500.0 + 40.0, y / 4500.0 + 40.0, seed + 7, 4)), x, y, e, sh);
		vec3 rock = t == 7 ? c : colr(7, x, y, e, sh);
		float r = smoothstep(0.684, 0.716, e + j);
		vec3 o = mix(low, rock, r);
		if (e > 0.73) o = mix(o, colr(8, x, y, e, sh), smoothstep(0.741, 0.759, e + j * 0.7));
		c = o;
	}
	return c;
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
	if (t >= 2 && t <= 8) c = blend_biomes(t, c, w.x, w.y, te, sh);
	bool wet = te < 0.40;
	if (t >= 11 && t <= 13 && !wet && te < 0.62 && distance(w, haven) > 1700.0)
		wet = abs(fbm(w.x / 8000.0 + 17.3, w.y / 8000.0 + 3.1, seed + 99, 3) - 0.5) < 0.009;   // river
	if (t >= 11 && t <= 13 && wet) {   // bridge deck over water, dark railings
		c = t == 13 ? vec3(44.0, 42.0, 40.0) : (t == 12 ? vec3(190.0, 170.0, 90.0) : vec3(88.0, 84.0, 78.0));
	}
	if (t == 5) {   // the dark forest floor shades in from the grass instead of a hard edge
		float ed = clamp((tm - 0.53) / 0.03, 0.0, 1.0);
		if (ed < 1.0) c = mix(colr(3, w.x, w.y, te, sh), c, ed * ed * (3.0 - 2.0 * ed));
	}
	COLOR = vec4(clamp(c / 255.0, 0.0, 1.0), 1.0);
}

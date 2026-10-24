shader_type canvas_item;
// Title screen only, over the flyover and under the menu (Greg, 2026-10-24): darkens the view
// as if it were lit by a candle. A warm pool of light around the plane flickers and breathes,
// the edges fall away into dark, and slow drifting cloud noise shades the view.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float dark = 0.18;            // how much darker the whole view gets
uniform vec2 center = vec2(0.64, 0.5);  // the candle: screen position of the light (0..1), follows the plane
uniform float radius = 0.78;          // where the light has fallen to the dark edge (share of the screen height)
uniform float edge = 0.69;            // how dark the edges get (0 none, 1 black; Greg 2026-10-24: 0.78, then edges 40% lighter)
uniform float bright = 1.4;           // brightness of the candlelight pool (Greg, 2026-10-24: brighter)
uniform float flicker = 0.07;         // how much the candle flickers
uniform float flicker_speed = 0.4;   // how fast it flickers (1 = the first version; Greg 2026-10-24: a bit slower)
uniform float clouds = 0.4;           // how strongly the cloud noise shades the view
uniform float cloud_size = 2.6;       // cloud blobs across the screen height
uniform float t = 0.0;                // time, seconds

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v / 0.9375;
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // width / height
	// candle flicker: a few uneven waves plus noise, so it never repeats evenly
	float ft = t * flicker_speed;
	float fl = sin(ft * 7.1) * 0.35 + sin(ft * 12.7 + 1.3) * 0.25 + (vnoise(vec2(ft * 5.3, 0.5)) - 0.5) * 1.2;
	float k = 1.0 + fl * flicker;
	vec2 wob = vec2(vnoise(vec2(ft * 1.7, 3.1)), vnoise(vec2(ft * 1.9, 8.4))) - 0.5;
	vec2 d = (SCREEN_UV - center - wob * 0.015) * vec2(aspect, 1.0);
	float light = 1.0 - smoothstep(radius * 0.2 * k, radius * k, length(d));
	// warm in the light, cool dim brown toward the edges
	vec3 warm = vec3(1.07, 0.96, 0.8);
	vec3 dim = vec3(0.62, 0.55, 0.5);
	c *= (1.0 - dark) * mix(dim * (1.0 - edge), warm * bright, light) * mix(1.0, k, light);
	// slow cloud noise drifting across, darker where it is thick
	vec2 q = SCREEN_UV * vec2(aspect, 1.0) * cloud_size;
	float n = fbm(q + vec2(t * 0.05, t * 0.02) + fbm(q * 0.6 - t * 0.03) * 0.8);
	c *= 1.0 - clouds * smoothstep(0.35, 0.8, n);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

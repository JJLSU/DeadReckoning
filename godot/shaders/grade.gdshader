shader_type canvas_item;
// Time-of-day colour grade over the game view (under the HUD and menus): render.gd sets the
// look for the hour (Render.update_grade). Shadows and highlights get their own tints, then
// saturation and a gentle contrast curve.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 high_tint = vec3(1.0);
uniform float sat = 1.0;
uniform float con = 1.0;
uniform float expo = 1.0;
// Cloud shadows drifting over the ground in flight (Greg, 2026-10-24; like the title screen's
// cloud noise, but fixed to the world and moving with the wind). Render.update_grade sets these.
uniform float cloud_amt = 0.0;          // 0 = off; how strongly the shadows darken
uniform vec2 cam = vec2(0.0);           // world point at the centre of the screen
uniform float scl = 1.0;                // screen pixels per world unit
uniform vec2 drift = vec2(0.0);         // how far the clouds have blown, world units
uniform float cloud_size = 1800.0;      // world units per noise cell (roughly a cloud's size)
uniform float t = 0.0;                  // seconds, slowly changes the cloud shapes

float c_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float c_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(c_hash(i), c_hash(i + vec2(1.0, 0.0)), f.x), mix(c_hash(i + vec2(0.0, 1.0)), c_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float c_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += c_noise(p) * a;
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v / 0.9375;
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * expo;
	if (cloud_amt > 0.0) {
		vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
		vec2 w = cam + (px - 0.5 / SCREEN_PIXEL_SIZE) / scl;
		vec2 q = (w - drift) / cloud_size;
		float n = c_fbm(q + c_fbm(q * 0.6 + vec2(t * 0.006, -t * 0.004)) * 0.8);
		float cover = smoothstep(0.45, 0.72, n);
		// shade under the clouds, a touch brighter in the sunny gaps
		c *= 1.0 + cloud_amt * (0.12 * (1.0 - cover) - cover);
	}
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float hi = smoothstep(0.15, 0.75, l);
	c *= mix(shadow_tint, high_tint, hi);
	l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	c = (c - 0.45) * con + 0.45;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

shader_type canvas_item;
// Night light mask for ground mode: dark overlay with soft holes for the player's light,
// flashlight cone, street lights and muzzle/explosion flashes (port of lightMask()).

uniform float dk = 0.0;
uniform vec2 screen = vec2(1280.0, 720.0);
uniform vec2 ppos = vec2(0.0);
uniform float r0 = 110.0;
uniform float cone_a = 0.0;
uniform float cone_l = 430.0;
uniform float flash_r = 0.0;
uniform int nlights = 0;
uniform vec3 lights[16];

void fragment() {
	vec2 p = UV * screen;
	float keep = 1.0;
	float d = distance(p, ppos);
	keep *= 1.0 - clamp(1.0 - d / r0, 0.0, 1.0);
	vec2 v = p - ppos;
	float ang = atan(v.y, v.x) - cone_a;
	ang = mod(ang + PI, 2.0 * PI) - PI;
	if (abs(ang) < 0.42 && d < cone_l) {
		float t = d / cone_l;
		float a = t < 0.7 ? mix(0.95, 0.6, t / 0.7) : mix(0.6, 0.0, (t - 0.7) / 0.3);
		keep *= 1.0 - a;
	}
	for (int i = 0; i < 16; i++) {
		if (i >= nlights) break;
		float dl = distance(p, lights[i].xy);
		keep *= 1.0 - 0.85 * clamp(1.0 - dl / lights[i].z, 0.0, 1.0);
	}
	if (flash_r > 0.0) keep *= 1.0 - 0.8 * clamp(1.0 - d / flash_r, 0.0, 1.0);
	COLOR = vec4(3.0 / 255.0, 5.0 / 255.0, 14.0 / 255.0, 0.92 * dk * keep);
}

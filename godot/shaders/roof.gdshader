shader_type canvas_item;
// Roof layer: fades soft circles out of the roofs of the buildings listed in rooms[]
// (screen-space rects). Each building can have two circles: one around the point where
// the ADS sightline crosses its opening (centres[i], faded by fades[i].x) and one around
// the player while peeking in at a door (ppos, faded by fades[i].y). Set by Render.draw_roofs().

uniform vec2 screen = vec2(1280.0, 720.0);
uniform vec2 ppos = vec2(0.0);
uniform float circ_r = 192.0;   // peek circle radius (screen px)
uniform float ads_r = 96.0;     // ADS circle radius (screen px)
uniform float peek_a = 0.3;     // roof opacity where it's cut
uniform int nrooms = 0;
uniform vec4 rooms[16];         // x0, y0, x1, y1
uniform vec2 centres[16];       // ADS crossing point
uniform vec2 fades[16];         // x = ADS circle, y = peek circle; 0 = solid roof, 1 = fully cut

float circ(vec2 p, vec2 c, float rad) {
	return 1.0 - smoothstep(rad * 0.75, rad * 1.25, distance(p, c));
}

void fragment() {
	if (nrooms > 0) {
		vec2 p = SCREEN_UV * screen;
		float cut = 0.0;
		for (int i = 0; i < 16; i++) {
			if (i >= nrooms) break;
			vec4 r = rooms[i];
			if (p.x >= r.x && p.y >= r.y && p.x <= r.z && p.y <= r.w)
				cut = max(cut, max(fades[i].x * circ(p, centres[i], ads_r), fades[i].y * circ(p, ppos, circ_r)));
		}
		COLOR.a *= mix(1.0, peek_a, cut);
	}
}

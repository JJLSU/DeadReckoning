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

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * expo;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float hi = smoothstep(0.15, 0.75, l);
	c *= mix(shadow_tint, high_tint, hi);
	l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	c = (c - 0.45) * con + 0.45;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

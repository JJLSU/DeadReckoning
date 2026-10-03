shader_type canvas_item;
// Whole-canvas colour filter, like the CSS filter on the game canvas: saturate() contrast().
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sat = 0.84;
uniform float con = 1.07;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	c = (c - 0.5) * con + 0.5;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

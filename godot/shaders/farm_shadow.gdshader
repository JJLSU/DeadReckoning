// The Failsafe farm's sun shadows, worked out once into a texture (Failsafe._bake_shadow)
// instead of on every pixel every frame: each texel marches toward the sun over the farm's
// height map, like farm_at() in trees.gdshader did. Redone when the sun has moved a little.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D farm_hgt : filter_linear, repeat_disable;
uniform vec2 farm_size = vec2(267.0, 207.0);
uniform float farm_h = 48.0;
uniform vec2 farm_sun = vec2(0.3, 0.5);   // shadow offset per unit of height, farm frame
uniform vec4 area = vec4(0.0, 0.0, 1.0, 1.0);   // what the texture covers: corner xy, size zw

float farm_ht(vec2 q) {
	vec2 uv = q / farm_size + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return textureLod(farm_hgt, uv, 0.0).r * farm_h;
}

void fragment() {
	vec2 q = area.xy + UV * area.zw;
	float h = farm_ht(q);
	float top = farm_h - h;
	// step about 2 units along the ground so thin things (poles, silos) still cast whole shadows
	int n = clamp(int(length(farm_sun) * top / 2.0), 8, 64);
	float sh = 0.0;
	for (int i = 1; i <= n && sh == 0.0; i++) {
		float t = 0.6 + top * float(i) / float(n);
		if (farm_ht(q - farm_sun * t) > h + t + 0.3) sh = 1.0;
	}
	COLOR = vec4(sh, 0.0, 0.0, 1.0);
}

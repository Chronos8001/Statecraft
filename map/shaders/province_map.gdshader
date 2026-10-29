shader_type canvas_item;
render_mode unshaded;

// Identifiants de provinces (RG8 : id = R + G * 256) et couleur affichée de chaque id.
uniform sampler2D province_ids : filter_nearest, repeat_disable;
uniform sampler2D province_colors : filter_nearest, repeat_disable;

uniform vec2 map_size;
uniform vec2 viewport_size;
uniform vec2 camera_center;
uniform float zoom = 1.0;
uniform vec4 background_color : source_color;

int province_at(vec2 map_position) {
	ivec2 texel = ivec2(
		int(mod(floor(map_position.x), map_size.x)),
		int(clamp(floor(map_position.y), 0.0, map_size.y - 1.0)));
	vec2 rg = texelFetch(province_ids, texel, 0).rg;
	return int(round(rg.r * 255.0)) + int(round(rg.g * 255.0)) * 256;
}

void fragment() {
	vec2 screen_position = UV * viewport_size;
	vec2 map_position = camera_center + (screen_position - viewport_size * 0.5) / zoom;
	if (map_position.y < 0.0 || map_position.y >= map_size.y) {
		COLOR = background_color;
	} else {
		int province_id = province_at(map_position);
		int lookup_width = textureSize(province_colors, 0).x;
		COLOR = texelFetch(province_colors, ivec2(province_id % lookup_width, province_id / lookup_width), 0);
	}
}

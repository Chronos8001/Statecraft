shader_type canvas_item;
render_mode unshaded;

// Identifiants de provinces (RG8 : id = R + G * 256).
uniform sampler2D province_ids : filter_nearest, repeat_disable;
// Par id de province : couleur affichée, et indice du pays propriétaire (RG8, 0 = mer, 1 = sans propriétaire).
uniform sampler2D province_colors : filter_nearest, repeat_disable;
uniform sampler2D province_owners : filter_nearest, repeat_disable;

uniform vec2 map_size;
uniform vec2 viewport_size;
uniform vec2 camera_center;
uniform float zoom = 1.0;
uniform vec4 background_color : source_color;

// Province sélectionnée (-1 = aucune), éclaircie vers selection_color.
uniform int selected_province = -1;
uniform vec4 selection_color : source_color = vec4(1.0);
uniform float selection_strength = 0.4;

// Frontières : épaisseur en pixels d'écran ; province_border_alpha dépend du zoom (calculé côté CPU).
uniform vec4 province_border_color : source_color;
uniform float province_border_width = 1.0;
uniform float province_border_alpha = 1.0;
uniform vec4 country_border_color : source_color;
uniform float country_border_width = 1.6;
// En dessous de ce zoom, un pixel d'écran couvre plusieurs pixels de carte : pas de lissage.
uniform float smooth_min_zoom = 1.0;

int decode_id(vec4 texel) {
	return int(round(texel.r * 255.0)) + int(round(texel.g * 255.0)) * 256;
}

int raw_id(ivec2 texel) {
	int width = int(map_size.x);
	ivec2 wrapped = ivec2(((texel.x % width) + width) % width, clamp(texel.y, 0, int(map_size.y) - 1));
	return decode_id(texelFetch(province_ids, wrapped, 0));
}

// Identifiant lissé : parmi les 4 pixels voisins, celui dont le poids bilinéaire cumulé est le plus fort.
// Les contours deviennent des courbes au lieu d'escaliers de pixels.
int smooth_id(vec2 map_position) {
	vec2 p = map_position - 0.5;
	vec2 base = floor(p);
	vec2 f = p - base;
	ivec2 t = ivec2(base);
	int ids[4];
	ids[0] = raw_id(t);
	ids[1] = raw_id(t + ivec2(1, 0));
	ids[2] = raw_id(t + ivec2(0, 1));
	ids[3] = raw_id(t + ivec2(1, 1));
	float weights[4] = float[4]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	int best = ids[0];
	float best_weight = -1.0;
	for (int i = 0; i < 4; i++) {
		float total = 0.0;
		for (int j = 0; j < 4; j++) {
			if (ids[j] == ids[i]) {
				total += weights[j];
			}
		}
		if (total > best_weight) {
			best_weight = total;
			best = ids[i];
		}
	}
	return best;
}

ivec2 lookup_texel(int province_id) {
	int lookup_width = textureSize(province_colors, 0).x;
	return ivec2(province_id % lookup_width, province_id / lookup_width);
}

int province_at(vec2 map_position) {
	return zoom >= smooth_min_zoom ? smooth_id(map_position) : raw_id(ivec2(floor(map_position)));
}

int owner_of(int province_id) {
	return decode_id(texelFetch(province_owners, lookup_texel(province_id), 0));
}

void fragment() {
	vec2 screen_position = UV * viewport_size;
	vec2 map_position = camera_center + (screen_position - viewport_size * 0.5) / zoom;
	if (map_position.y < 0.0 || map_position.y >= map_size.y) {
		COLOR = background_color;
	} else {
		int province_id = province_at(map_position);
		vec4 color = texelFetch(province_colors, lookup_texel(province_id), 0);
		if (province_id == selected_province && province_id > 0) {
			color.rgb = mix(color.rgb, selection_color.rgb, selection_strength);
		}
		int owner = owner_of(province_id);
		// Mêmes voisins pour les deux types de frontières ; seule la frontière de pays est plus épaisse.
		vec2 directions[4] = vec2[4](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
		float radius = country_border_width / zoom;
		float province_edges = 0.0;
		float country_edges = 0.0;
		for (int i = 0; i < 4; i++) {
			int neighbour = province_at(map_position + directions[i] * radius);
			if (neighbour != province_id) {
				if (owner_of(neighbour) != owner) {
					country_edges += 1.0;
				} else if (province_id > 0) {
					province_edges += 1.0;
				}
			}
		}
		province_edges *= province_border_width / country_border_width;
		float province_edge = clamp(province_edges * 0.5, 0.0, 1.0) * province_border_alpha * province_border_color.a;
		float country_edge = clamp(country_edges * 0.5, 0.0, 1.0) * country_border_color.a;
		color.rgb = mix(color.rgb, province_border_color.rgb, province_edge);
		color.rgb = mix(color.rgb, country_border_color.rgb, country_edge);
		COLOR = color;
	}
}

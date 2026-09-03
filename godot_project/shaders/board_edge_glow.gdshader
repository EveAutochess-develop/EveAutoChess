shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float play_radius = 19.5;
uniform float y_min = 0.0;
uniform float y_max = 1.0;
uniform float peak_alpha = 0.08;
uniform float fade_cells = 1.0;
uniform vec4 glow_color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
/// 0 = cylinder side wall, 1 = top cap (y_max), 2 = bottom cap (y_min).
uniform int surface_kind = 0;
uniform int ship_count = 0;

const int MAX_SHIPS = 48;
uniform vec4 ship_spheres[MAX_SHIPS];

float angle_diff(float a, float b) {
	float d = abs(a - b);
	return min(d, TAU - d);
}

/// Circular patch on side wall; only when hull outer edge is near play-disk rim.
float ship_side_alpha(vec3 p, vec3 c, float r) {
	float fade_w = max(r * fade_cells, 1e-5);
	float hull_to_rim = play_radius - length(c.xz) - r;
	if (hull_to_rim > fade_w || hull_to_rim < -fade_w) {
		return 0.0;
	}
	float edge_gate = 1.0 - smoothstep(0.0, fade_w, abs(hull_to_rim));
	if (edge_gate <= 0.001) {
		return 0.0;
	}
	float ang_p = atan(p.x, p.z);
	float ang_c = atan(c.x, c.z);
	float arc_dist = play_radius * angle_diff(ang_p, ang_c);
	float tangential = 1.0 - smoothstep(0.0, fade_w, arc_dist);
	float vertical = 1.0 - smoothstep(0.0, fade_w, abs(p.y - c.y));
	return peak_alpha * edge_gate * tangential * vertical;
}

/// Circular patch on top/bottom cap; only when hull touches that cap plane.
float ship_cap_alpha(vec3 p, vec3 c, float r, bool is_top) {
	float fade_w = max(r * fade_cells, 1e-5);
	float cap_y = is_top ? y_max : y_min;
	float hull_gap = is_top ? (cap_y - (c.y + r)) : ((c.y - r) - cap_y);
	if (hull_gap > fade_w) {
		return 0.0;
	}
	float vertical = 1.0 - smoothstep(0.0, fade_w, max(hull_gap, 0.0));
	if (vertical <= 0.001) {
		return 0.0;
	}
	vec2 d_xz = p.xz - c.xz;
	float planar = 1.0 - smoothstep(0.0, fade_w, length(d_xz));
	return peak_alpha * vertical * planar;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float alpha = 0.0;
	vec3 wp = world_pos;
	int n = clamp(ship_count, 0, MAX_SHIPS);
	for (int i = 0; i < MAX_SHIPS; i++) {
		if (i >= n) {
			break;
		}
		vec3 c = ship_spheres[i].xyz;
		float r = ship_spheres[i].w;
		if (r <= 1e-4) {
			continue;
		}
		float local_a = 0.0;
		if (surface_kind == 0) {
			local_a = ship_side_alpha(wp, c, r);
		} else {
			local_a = ship_cap_alpha(wp, c, r, surface_kind == 1);
		}
		alpha = max(alpha, local_a);
	}
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(alpha, 0.0, peak_alpha);
}

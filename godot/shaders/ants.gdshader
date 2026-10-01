shader_type spatial;
render_mode vertex_lighting, cull_disabled;

uniform vec4 ant_color : source_color = vec4(0.24,0.075,0.025,1.0);
uniform float simulation_time = 0.0;

void vertex() {
	float copy = UV2.x;
	if (copy >= INSTANCE_CUSTOM.r) {
		VERTEX = vec3(0.0);
	} else {
		float phase = simulation_time * 28.0 * INSTANCE_CUSTOM.a + INSTANCE_CUSTOM.b * 6.283185 + UV.y;
		if (UV.x > 0.5 && UV.x < 1.5) {
			float reach = clamp((abs(VERTEX.x) - 0.06) / 0.33,0.0,1.0);
			VERTEX.z += sin(phase) * 0.11 * reach;
			VERTEX.y += max(0.0,cos(phase)) * 0.065 * reach;
		} else if (UV.x > 1.5) {
			VERTEX.x += sin(phase * 0.31) * 0.018;
		}
		if (copy > 0.5) {
			float angle = copy * 2.399963;
			vec2 offset = vec2(sin(angle),cos(angle)) * sqrt(copy / 8.0) * INSTANCE_CUSTOM.g;
			VERTEX.xz += offset;
		}
	}
}

void fragment() {
	ALBEDO = ant_color.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}

shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 texture_scale = vec2(1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform bool vertex_snap = true;
uniform bool swarm_enabled = false;
varying vec2 affine_uv;
varying float affine_w;
uniform sampler2D swarm_data : filter_linear, repeat_disable;
uniform vec4 ant_color : source_color = vec4(0.24,0.075,0.025,1.0);
uniform float simulation_time = 0.0;
uniform float ant_speed = 0.045;
uniform float visual_length = 0.032;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX,1.0);
	if (vertex_snap && clip.w > 0.01) {
		vec2 grid = vec2(480.0,270.0);
		clip.xy = floor(clip.xy / clip.w * grid + 0.5) / grid * clip.w;
	}
	POSITION = clip;
	affine_uv = UV * clip.w; affine_w = clip.w;
}

void fragment() {
	vec3 ground = texture(albedo_texture,(affine_uv/affine_w)*texture_scale).rgb*tint.rgb;
	ALBEDO = ground; ROUGHNESS = 1.0;
	if (swarm_enabled) {
		vec3 data = texture(swarm_data,UV).rgb;
		float coverage = data.r;
		vec2 direction = data.gb * 2.0 - 1.0;
		float pixel_span = max(length(dFdx(world_position.xz)),length(dFdy(world_position.xz)));
		float pitch = max(visual_length * 0.85,pixel_span * 0.9);
		vec2 pattern = (world_position.xz - direction * ant_speed * simulation_time) / pitch;
		vec2 cell = floor(pattern);
		vec2 local = fract(pattern) - vec2(0.5);
		float angle = hash(cell + 9.3) * 6.283185;
		vec2 q = mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle))) * local;
		float abdomen = 1.0 - smoothstep(0.6,1.0,length(q / vec2(0.18,0.34)));
		float head = 1.0 - smoothstep(0.55,1.0,length((q - vec2(0,0.30)) / vec2(0.12,0.13)));
		float grain = max(abdomen,head) * step(hash(cell),coverage);
		float opacity = clamp(coverage * 0.72 + grain * coverage * 0.55,0.0,0.98);
		vec3 insects = ant_color.rgb * mix(0.38,0.85,grain) + vec3(0.012);
		ALBEDO = mix(ground,insects,opacity);
	}
}

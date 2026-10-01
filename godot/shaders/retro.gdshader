shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 texture_scale = vec2(1.0);
uniform bool vertex_snap = true;
varying vec2 affine_uv;
varying float affine_w;
void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (vertex_snap && clip.w > 0.01) {
		vec2 grid = vec2(480.0, 270.0);
		clip.xy = floor(clip.xy / clip.w * grid + 0.5) / grid * clip.w;
	}
	POSITION = clip;
	affine_uv = UV * clip.w;
	affine_w = clip.w;
}
void fragment() {
	vec2 uv = affine_uv / affine_w;
	ALBEDO = texture(albedo_texture, uv * texture_scale).rgb * tint.rgb;
	ROUGHNESS = 1.0;
}

shader_type canvas_item;
uniform bool enabled = true;
uniform float darkness = 0.12;
void fragment() {
	vec3 col = texture(TEXTURE, UV).rgb;
	if (enabled) {
		ivec2 pixel = ivec2(floor(UV * vec2(textureSize(TEXTURE, 0))));
		int bayer[16] = int[](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5);
		float ordered = (float(bayer[(pixel.y % 4)*4+(pixel.x % 4)]) / 16.0 - 0.5) / 31.0;
		col = floor(clamp(col + ordered, 0.0, 1.0) * 31.0 + 0.5) / 31.0;
		float vignette = 1.0 - darkness * pow(length((UV - 0.5) * vec2(1.0,0.8)), 1.4);
		col *= vignette;
	}
	COLOR = vec4(col, 1.0);
}

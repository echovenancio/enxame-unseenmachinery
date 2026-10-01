shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 ant_color : source_color = vec4(0.24,0.075,0.025,1.0);
uniform float simulation_time = 0.0;
varying float tripod;

void vertex() {
	float copy = UV2.x;
	tripod = sin(simulation_time * 28.0 * INSTANCE_CUSTOM.a + INSTANCE_CUSTOM.b * 6.283185);
	if (copy >= INSTANCE_CUSTOM.r) {
		VERTEX = vec3(0.0);
	} else if (copy > 0.5) {
		float angle = copy * 2.399963;
		VERTEX.xz += vec2(sin(angle),cos(angle)) * sqrt(copy / 8.0) * INSTANCE_CUSTOM.g;
	}
}

float line_distance(vec2 p,vec2 a,vec2 b) {
	vec2 ab = b-a;
	return length(p-a-ab*clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0));
}

void fragment() {
	vec2 q = (UV-0.5)*vec2(0.85,1.10);
	float body = min(length((q-vec2(0,-0.23))/vec2(0.16,0.23)),length((q-vec2(0,0.05))/vec2(0.07,0.10)));
	body = min(body,length((q-vec2(0,0.28))/vec2(0.10,0.12)));
	float leg = 1.0;
	for (int side=0;side<2;side++) {
		float sign_value = side==0 ? -1.0 : 1.0;
		for (int row=0;row<3;row++) {
			float phase = (row+side)%2==0 ? tripod : -tripod;
			vec2 hip = vec2(sign_value*0.045,-0.10+float(row)*0.13);
			vec2 toe = vec2(sign_value*0.39,-0.25+float(row)*0.28+phase*0.075);
			leg = min(leg,line_distance(q,hip,toe));
		}
		leg = min(leg,line_distance(q,vec2(sign_value*0.055,0.33),vec2(sign_value*0.18,0.50)));
	}
	ALBEDO = ant_color.rgb * COLOR.rgb * 0.72;
	ALPHA = body<1.0 || leg<0.017 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

shader_type spatial;
// Lightweight Mediterranean water (works on GL Compatibility / mobile).
// Base colour keeps the HARAQ sea signature #1E4C5A.
render_mode cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.118, 0.298, 0.353, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.52, 0.55, 1.0);
uniform float wave_height = 0.18;
uniform float wave_speed = 0.8;

varying float v_wave;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float h = sin(w.x * 0.15 + t) * 0.5 + sin(w.z * 0.22 - t * 1.3) * 0.35 + sin((w.x + w.z) * 0.5 + t * 2.0) * 0.15;
	VERTEX.y += h * wave_height;
	v_wave = h;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, clamp(v_wave * 0.3 + 0.3, 0.0, 1.0));
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.6 + fres * 0.4;
}

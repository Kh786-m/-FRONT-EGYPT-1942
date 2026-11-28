// HARAQ Mediterranean: stylised opaque sea (#1E4C5A deep, turquoise shallows), rolling waves,
// scrolling normals, Fresnel sky tint and animated surf along the beach.
shader_type spatial;
render_mode specular_schlick_ggx, cull_back, fog_disabled;

uniform vec4 deep_color : source_color = vec4(0.07, 0.22, 0.28, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.48, 0.5, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.42, 0.6, 0.64, 1.0);
uniform vec4 foam_color : source_color = vec4(0.953, 0.902, 0.816, 1.0);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform float shore_base = -101.0;

varying vec3 wpos;

float shore_z(float x) {
	return shore_base + 5.0 * sin(x * 0.021) + 2.5 * sin(x * 0.057 + 1.3);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.07 + TIME * 0.9) * 0.10 + sin(wpos.z * 0.11 - TIME * 1.3 + wpos.x * 0.03) * 0.09;
	VERTEX.y += w;
	wpos.y += w;
}

void fragment() {
	float d = shore_z(wpos.x) - wpos.z;
	float depthf = clamp(d / 55.0, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, sqrt(depthf));
	vec2 uv1 = wpos.xz * 0.035 + vec2(TIME * 0.012, TIME * 0.02);
	vec2 uv2 = wpos.xz * 0.011 - vec2(TIME * 0.008, -TIME * 0.006);
	vec3 n = mix(texture(wave_normal, uv1).rgb, texture(wave_normal, uv2).rgb, 0.5);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, horizon_color.rgb, fres * 0.3);
	float fn = texture(foam_noise, wpos.xz * 0.06 + vec2(TIME * 0.02, 0.0)).r;
	float surf = sin(d * 0.85 - TIME * 1.7) * 0.5 + 0.5;
	float foam = (1.0 - smoothstep(0.0, 7.0, d)) * smoothstep(0.6, 0.95, surf * 0.7 + fn * 0.6);
	foam = max(foam, 1.0 - smoothstep(-0.5, 1.6, d + fn * 1.5));
	ALBEDO = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(0.14, 0.85, foam);
	SPECULAR = 0.3;
}

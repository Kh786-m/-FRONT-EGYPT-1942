// HARAQ desert terrain: two CC0 sand textures blended by large-scale noise (no visible tiling),
// graded toward the HARAQ sand palette, darker wet sand along the Mediterranean shore.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coarse_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coarse_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 palette_sand : source_color = vec4(0.894, 0.824, 0.690, 1.0);
uniform vec4 palette_khaki : source_color = vec4(0.541, 0.439, 0.282, 1.0);
uniform float shore_base = -101.0;
uniform float sea_level = -0.55;

varying vec3 wpos;
varying vec3 wnorm;

float shore_z(float x) {
	return shore_base + 5.0 * sin(x * 0.021) + 2.5 * sin(x * 0.057 + 1.3);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz;
	float m = texture(macro_noise, uv * 0.0045).r;
	float m2 = texture(macro_noise, uv * 0.027 + vec2(0.37, 0.11)).r;
	vec3 s_near = texture(sand_albedo, uv * 0.21).rgb;
	vec3 s_far = texture(sand_albedo, uv * 0.047 + vec2(0.5)).rgb;
	vec3 sand = mix(s_near, s_far, 0.45);
	vec3 coarse = texture(coarse_albedo, uv * 0.16).rgb;
	float blend = smoothstep(0.40, 0.66, m) * 0.75;
	// Dune crests a little lighter, troughs / slopes a little coarser.
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	blend = clamp(blend + slope * 2.5, 0.0, 0.85);
	vec3 col = mix(sand, coarse, blend);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(palette_khaki.rgb, palette_sand.rgb, clamp(lum * 1.35, 0.0, 1.0));
	col = mix(col, graded * (0.75 + lum * 0.55), 0.6);
	col *= mix(0.86, 1.08, m2);
	// Wet sand near the waterline.
	float d = wpos.z - shore_z(wpos.x);
	float wet = 1.0 - smoothstep(1.0, 10.0, d);
	vec3 wc = texture(wet_albedo, uv * 0.18).rgb * vec3(0.78, 0.72, 0.62);
	col = mix(col, wc, wet * 0.9);
	ALBEDO = col;
	vec3 n1 = texture(sand_normal, uv * 0.21).rgb;
	vec3 n2 = texture(coarse_normal, uv * 0.16).rgb;
	vec3 n3 = texture(wet_normal, uv * 0.18).rgb;
	NORMAL_MAP = mix(mix(n1, n2, blend), n3, wet);
	NORMAL_MAP_DEPTH = 0.9;
	ROUGHNESS = mix(0.96, 0.45, wet);
	SPECULAR = mix(0.25, 0.5, wet);
}

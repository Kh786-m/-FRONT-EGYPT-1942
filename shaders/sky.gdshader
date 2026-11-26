// HARAQ desert sky: hazy bone horizon, sea-tinted zenith, warm sun disk + glow, soft high clouds.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.30, 0.52, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.87, 0.76);
uniform vec3 ground_color : source_color = vec3(0.80, 0.71, 0.56);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.62);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_amount = 0.45;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.42));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	// Sun.
	float sd = dot(d, LIGHT0_DIRECTION);
	float glow = pow(max(sd, 0.0), 6.0) * 0.28 + pow(max(sd, 0.0), 90.0) * 0.7;
	col += sun_color * glow;
	col = mix(col, sun_color * 6.0, smoothstep(0.99955, 0.9998, sd));
	// High wispy clouds (projected onto a dome).
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.18);
		float c = texture(cloud_noise, uv * 0.11 + vec2(0.3, 0.7)).r;
		float c2 = texture(cloud_noise, uv * 0.37).r;
		c = smoothstep(0.52, 0.86, c * 0.75 + c2 * 0.35) * smoothstep(0.02, 0.3, h) * cloud_amount;
		col = mix(col, horizon_color * 1.08 + sun_color * glow * 0.4, c);
	}
	COLOR = col;
}

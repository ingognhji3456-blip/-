shader_type canvas_item;
// 땅: 구워 둔 색 지도(1000px) 위에 지역별 바닥 무늬와 잔 노이즈, 물결을 얹어요

uniform sampler2D info_tex : filter_nearest;          // R=지역*32, G=물(255)/얼음(128), B=길
uniform sampler2D det0 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det1 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det2 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det3 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det4 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det5 : repeat_enable, filter_linear_mipmap;
uniform sampler2D det6 : repeat_enable, filter_linear_mipmap;
uniform float world_size = 8000.0;
uniform vec2 lair = vec2(620.0, 4000.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

vec4 detail(int z, vec2 uv) {
	if (z == 0) return texture(det0, uv);
	if (z == 1) return texture(det1, uv);
	if (z == 2) return texture(det2, uv);
	if (z == 3) return texture(det3, uv);
	if (z == 4) return texture(det4, uv);
	if (z == 5) return texture(det5, uv);
	return texture(det6, uv);
}

void fragment() {
	vec2 wp = UV * world_size;
	vec3 col = texture(TEXTURE, UV).rgb;
	vec4 inf = texture(info_tex, UV);
	int z = int(round(inf.r * 255.0 / 32.0));
	bool water = inf.g > 0.9;
	bool ice = inf.g > 0.4 && inf.g < 0.6;
	bool road = inf.b > 0.5;
	// 잔 노이즈로 흐릿함을 덜어요
	float n = vnoise(wp / 9.0) * 0.5 + vnoise(wp / 23.0) * 0.35 + vnoise(wp / 61.0) * 0.15;
	if (water) {
		float w = sin(wp.x * 0.045 + TIME * 1.3 + vnoise(wp / 40.0) * 6.0) * sin(wp.y * 0.06 - TIME * 0.9);
		col *= 0.94 + 0.08 * n;
		col += vec3(0.55, 0.75, 0.85) * smoothstep(0.82, 0.98, w) * 0.22;
	} else if (ice) {
		col *= 0.97 + 0.06 * n;
		col += vec3(0.8, 0.9, 1.0) * smoothstep(0.93, 0.99, vnoise(wp / 5.0)) * 0.12;
	} else {
		col *= 0.9 + 0.2 * n;
		if (!road) {
			vec4 d = detail(z, wp / 256.0);
			col = mix(col, d.rgb, d.a * 0.85);
		} else {
			col *= 0.95 + 0.1 * vnoise(wp / 3.0);
		}
	}
	// 용의 둥지: 그을린 땅
	float ld = length(wp - lair);
	col = mix(col, vec3(0.16, 0.055, 0.03), 0.7 * (1.0 - smoothstep(20.0, 170.0, ld)));
	COLOR = vec4(col, 1.0);
}

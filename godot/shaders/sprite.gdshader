shader_type canvas_item;
// 맞으면 하얗게 번쩍, 공격 예고/분노 때는 테두리가 빛나요

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(0.06, 0.05, 0.04, 0.5);
uniform float rim_px = 1.2;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (rim_color.a > 0.01 && rim_px > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * rim_px * 2.0;
		float a = 0.0;
		a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
		a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
		a = max(a, texture(TEXTURE, UV + px * 0.7).a);
		a = max(a, texture(TEXTURE, UV - px * 0.7).a);
		a = max(a, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.7).a);
		a = max(a, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.7).a);
		float ra = rim_color.a * a * (1.0 - c.a);
		float oa = c.a + ra;
		c.rgb = (c.rgb * c.a + rim_color.rgb * ra) / max(oa, 0.001);
		c.a = oa;
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash * step(0.01, c.a));
	COLOR = c * COLOR;
}

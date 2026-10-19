shader_type canvas_item;
// Swaps the sprite sheets' key colours for each player's real colours.
// Body key colours: skin = magenta, shirt = red, shorts = blue, socks = yellow.
// Hair sprites use green. Each key has a light (255) and dark (150) shade.

uniform vec4 skin : source_color = vec4(0.94, 0.75, 0.6, 1.0);
uniform vec4 shirt : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 shorts : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 socks : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 hair : source_color = vec4(0.2, 0.14, 0.08, 1.0);
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);

const float D = 150.0 / 255.0;
const float SHADE = 0.62;

bool near(vec3 a, vec3 b) {
	return distance(a, b) < 0.1;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 o = c.rgb;
	if (near(c.rgb, vec3(1.0, 0.0, 1.0))) o = skin.rgb;
	else if (near(c.rgb, vec3(D, 0.0, D))) o = skin.rgb * SHADE;
	else if (near(c.rgb, vec3(1.0, 0.0, 0.0))) o = shirt.rgb;
	else if (near(c.rgb, vec3(D, 0.0, 0.0))) o = shirt.rgb * SHADE;
	else if (near(c.rgb, vec3(0.0, 0.0, 1.0))) o = shorts.rgb;
	else if (near(c.rgb, vec3(0.0, 0.0, D))) o = shorts.rgb * SHADE;
	else if (near(c.rgb, vec3(1.0, 1.0, 0.0))) o = socks.rgb;
	else if (near(c.rgb, vec3(D, D, 0.0))) o = socks.rgb * SHADE;
	else if (near(c.rgb, vec3(0.0, 1.0, 0.0))) o = hair.rgb;
	else if (near(c.rgb, vec3(0.0, D, 0.0))) o = hair.rgb * SHADE;
	o = mix(o, flash.rgb, flash.a);
	COLOR = vec4(o, c.a * COLOR.a);
}

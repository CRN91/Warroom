shader_type canvas_item;

// The obnoxious color you painted the uniform in your software
uniform vec4 origin_color : source_color = vec4(1.0, 0.0, 1.0, 1.0); // Default is Magenta
// The color you want it to become in-game
uniform vec4 new_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How strict the color matching is
uniform float tolerance : hint_range(0.0, 1.0) = 0.1;

void fragment() {
    vec4 current_pixel = texture(TEXTURE, UV);
    
    // If the pixel matches our origin color, swap it!
    if (distance(current_pixel.rgb, origin_color.rgb) < tolerance) {
        COLOR = vec4(new_color.rgb, current_pixel.a);
    } else {
        COLOR = current_pixel; // Leave guns, skin, and boots alone
    }
}
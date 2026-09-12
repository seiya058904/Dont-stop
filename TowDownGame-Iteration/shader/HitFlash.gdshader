shader_type canvas_item;
uniform float flash : hint_range(0.0,1.0) = 0.0;
void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    vec2 step_uv = TEXTURE_PIXEL_SIZE;
    float neighbor = min(min(texture(TEXTURE,UV+vec2(step_uv.x,0.0)).a,texture(TEXTURE,UV-vec2(step_uv.x,0.0)).a),min(texture(TEXTURE,UV+vec2(0.0,step_uv.y)).a,texture(TEXTURE,UV-vec2(0.0,step_uv.y)).a));
    float rim = clamp(pixel.a-neighbor,0.0,1.0);
    vec3 readable = mix(pixel.rgb,vec3(0.42,0.58,0.64),rim*0.7);
    COLOR = vec4(mix(readable,vec3(1.0),flash),pixel.a);
}

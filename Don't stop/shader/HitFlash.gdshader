shader_type canvas_item;
global uniform float b19_enchantment_time;
uniform float enchantment_tier = 0.0;
uniform float enchantment_phase = 0.0;
uniform float flash : hint_range(0.0,1.0) = 0.0;
void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    vec2 step_uv = TEXTURE_PIXEL_SIZE;
    float neighbor = min(min(texture(TEXTURE,UV+vec2(step_uv.x,0.0)).a,texture(TEXTURE,UV-vec2(step_uv.x,0.0)).a),min(texture(TEXTURE,UV+vec2(0.0,step_uv.y)).a,texture(TEXTURE,UV-vec2(0.0,step_uv.y)).a));
    float rim = clamp(pixel.a-neighbor,0.0,1.0);
    vec3 readable = mix(pixel.rgb,vec3(0.42,0.58,0.64),rim*0.7);
    // Pixel-stepped diagonal sheen, clipped by the original sprite alpha.
    // No extra sprite, particle, polygon or material update per actor/frame.
    if (enchantment_tier > 0.0) {
        vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
        float phase = fract((texel.x + texel.y * 0.75) / 18.0
            - b19_enchantment_time * 0.3125 + enchantment_phase);
        float shoulder = step(0.38, phase) * (1.0 - step(0.82, phase));
        float core = step(0.56, phase) * (1.0 - step(0.70, phase));
        float heavy = step(1.5, enchantment_tier);
        vec3 violet = mix(vec3(0.38, 0.27, 0.82), vec3(0.64, 0.24, 0.88), heavy);
        vec3 sheen = mix(vec3(0.70, 0.63, 1.0), vec3(0.90, 0.57, 1.0), heavy);
        float light = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        readable = mix(readable, violet * (0.55 + light * 0.45), 0.14 + heavy * 0.06);
        readable = mix(readable, sheen, shoulder * (0.22 + heavy * 0.10)
            + core * (0.22 + heavy * 0.06));
    }
    // Hit feedback remains last; reduced-flash still controls only the flash.
    COLOR = vec4(mix(readable,vec3(1.0),flash),pixel.a);
}

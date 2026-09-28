extends Control
## A single bounded canvas pass. No screen texture, physics, RNG, or light shadows.
var clock := 0.0
var tick := 0.0
var vignette: ColorRect
const INKS = {"R1":Color("cbaa72"),"R2":Color("d4b476"),"R3":Color("96d9e6"),"R4":Color("ed9162"),"R5":Color("a1c589"),"R6":Color("b2a4ef"),"R7":Color("85d5b7"),"R8":Color("c5a0ef")}
var ink := Color("cbaa72")

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; uniform bool menu = true; void fragment(){ vec2 p=UV*2.0-1.0; float edge=smoothstep(0.25,1.35,length(p*vec2(0.8,1.0))); float left=menu ? (1.0-smoothstep(0.0,0.64,UV.x))*0.88 : 0.0; COLOR=vec4(0.025,0.045,0.065,max(edge*0.3,left)); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

func _process(delta):
	clock += delta
	tick += delta
	if tick < 0.05: return
	tick = 0.0
	var region := "R%d" % (1+maxi(0,LevelServer.level-1)/5)
	ink = INKS.get(region,INKS.R1)
	vignette.material.set_shader_parameter("menu",not Utils.is_game_start)
	queue_redraw()

func _draw():
	# Sparse, slow dust. A calm counterpoint to the faster hostile telegraphs.
	var count := 14 if not Utils.is_game_start or LevelServer.state == "CAMP" else 8
	for i in count:
		var p := Vector2(fposmod(i*73.7+sin(clock*0.2+i)*9,size.x),fposmod(i*41.3-clock*(1.2+i%3),size.y))
		var alpha := (0.12+0.12*sin(clock*0.6+i))*(0.5 if Combat.reduced_flash else 1.0)
		draw_circle(p,1.5,Color(ink,alpha*0.18))
		draw_rect(Rect2(p,Vector2(0.55,0.55)),Color(ink,alpha))

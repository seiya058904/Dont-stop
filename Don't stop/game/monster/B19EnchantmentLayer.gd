extends Node2D

## B19.1: one pause-aware clock for the glint in the actors' existing materials.
## Only health bars are external; the enchantment follows the actual sprite mask.
var animation_time := 0.0
var animation_frame := -1
var last_combat := false
var epoch := -1
var draw_usec := 0
var draw_passes := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 1

func _process(delta: float) -> void:
	var in_combat: bool = LevelServer.state == "COMBAT"
	if not in_combat:
		if last_combat:
			last_combat = false
			queue_redraw()
		return
	if epoch != LevelServer.epoch:
		epoch = LevelServer.epoch
		animation_time = 0.0
	last_combat = true
	animation_time = fmod(animation_time+delta,64.0)
	animation_frame = int(animation_time*10.0)
	RenderingServer.global_shader_parameter_set("b19_enchantment_time",animation_time)
	queue_redraw()

func _draw() -> void:
	if not last_combat or LevelServer.state != "COMBAT" or epoch != LevelServer.epoch: return
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	var inverse := global_transform.affine_inverse()
	# Keep actor order. Each contiguous equal-width run is one draw command;
	# transform endpoints instead of emitting a canvas transform for every bar.
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var width := -1.0
	for actor in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(actor) or actor.is_die or actor.is_queued_for_deletion() or not actor.is_visible_in_tree(): continue
		if not actor.get_meta("variant_applied",false): continue
		var transform: Transform2D = inverse*actor.global_transform
		var giant: bool = bool(actor.get_meta("giant",false))
		var radius := 23.0 if giant else 13.0
		var center := Vector2(0,-18 if giant else -9)
		var color := Color("eeb65d") if giant else Color("ad91dc")
		var fraction := clampf(float(actor.HP)/maxf(1.0,float(actor.get_meta("initialized_hp",actor.HP))),0,1)
		var line_width := 2.0*transform.y.length()
		# Uniform actor scaling is the shipped path. Preserve exact rasterization
		# for a future skew/nonuniform transform using the original drawing call.
		if not is_equal_approx(transform.x.length(),transform.y.length()) or absf(transform.x.dot(transform.y)) > 0.0001:
			if not points.is_empty(): draw_multiline_colors(points,colors,width); points.clear(); colors.clear()
			draw_set_transform_matrix(transform)
			draw_line(center+Vector2(-radius,-radius-7),center+Vector2(-radius+radius*2*fraction,-radius-7),color,2)
			draw_set_transform_matrix(Transform2D.IDENTITY)
			continue
		if width != line_width and not points.is_empty():
			draw_multiline_colors(points,colors,width)
			points.clear(); colors.clear()
		width = line_width
		points.append(transform*(center+Vector2(-radius,-radius-7)))
		points.append(transform*(center+Vector2(-radius+radius*2*fraction,-radius-7)))
		colors.append(color)
	if not points.is_empty(): draw_multiline_colors(points,colors,width)
	if B11Probe.enabled:
		draw_usec += Time.get_ticks_usec()-started
		draw_passes += 1

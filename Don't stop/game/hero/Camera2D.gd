extends Camera2D

var is_shake = false
var shake_tween: Tween
const MAX_LOOK_AHEAD := 48.0

var center_horizontal = false
var center_vertical = false
var center_horizontal_pos:int
var center_vertical_pos:int


func _physics_process(delta: float) -> void:
	# Camera2D interpolates these physics snapshots at each render frame.
	# Keep look-ahead and shake on the same clock as the tracking anchor.
	# Screen-space aim cannot inherit the previous arena's world transform.
	# Bound the lead so even a cursor outside the window keeps the hero in view.
	var cursor_delta := Utils.get_aim_viewport_position()-get_viewport_rect().size*0.5
	var lead := (cursor_delta/zoom*0.5).limit_length(MAX_LOOK_AHEAD)
	position = position.lerp(lead,1.0-exp(-6.0*delta))
	if center_horizontal:
		global_position.x = center_horizontal_pos
	if center_vertical:
		global_position.y = center_vertical_pos

func _ready():
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()
	add_to_group("camera")

func reset_after_teleport() -> void:
	if shake_tween and shake_tween.is_valid(): shake_tween.kill()
	is_shake = false
	position = Vector2.ZERO
	offset = Vector2.ZERO
	# With interpolation, force_update_scroll reads cached snapshots. Align the
	# tracking target and clear smoothing BEFORE replacing both snapshots, or
	# the very first frame still displays the arena we just left.
	align()
	reset_smoothing()
	reset_physics_interpolation()
	force_update_scroll()

func shootShake(_step):
	if float(Utils.shake) <= 0:
		return
	if is_shake:
		return
	is_shake = true
	_step *= Utils.shake
	shake_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_trans(Tween.TRANS_LINEAR)
	shake_tween.tween_property(self,"offset",_step,0.1)
	shake_tween.tween_property(self,"offset",Vector2.ZERO,0.1)
	shake_tween.tween_callback(func end():
		is_shake = false)

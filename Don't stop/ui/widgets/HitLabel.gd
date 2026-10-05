extends Label

static var live_count := 0
var age := 0.0
var origin_y := 0.0

func _enter_tree() -> void:
	live_count += 1

func _exit_tree() -> void:
	live_count -= 1

func _ready() -> void:
	add_to_group("damage_labels")
	# One feedback layer keeps numbers readable and consecutive font draws batchable.
	z_as_relative = false
	z_index = 8
	# The arena is 410x230: the theme's default 16px obscures the actor on fast fire.
	add_theme_font_size_override("font_size",8)
	add_theme_color_override("font_shadow_color",Color("071018"))
	add_theme_constant_override("shadow_offset_x",0)
	add_theme_constant_override("shadow_offset_y",1)
	# B11.1 test-only counter (game/diag/B11Probe.gd): damage-number churn rate.
	if B11Probe.enabled: B11Probe.labels_created += 1
	origin_y = position.y
	_update_motion()

func _process(delta: float) -> void:
	age += delta
	if age >= 1.0:
		queue_free()
		return
	_update_motion()

func _update_motion() -> void:
	# The same three cubic-out curves and one-second parent-owned lifetime,
	# without allocating a Tween and four Tweeners for every damage number.
	scale = Vector2.ONE*(1.0+0.2*pow(1.0-clampf(age/0.16,0,1),3))
	position.y = origin_y-24.0*(1.0-pow(1.0-clampf(age/0.65,0,1),3))
	modulate.a = pow(1.0-clampf((age-0.55)/0.22,0,1),3)

func setNumber(number):
	# The existing feedback channel also carries status text such as "护盾".
	if not (number is int or number is float):
		text = str(number)
		return
	# Display precision only: the hit pipeline retains the unrounded value.
	var value := float(number)
	if value != 0.0 and absf(value) < 0.01:
		text = "<0.01" if value > 0 else "−<0.01"
	else:
		text = ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func setColor(color):
	set("theme_override_colors/font_color",color)

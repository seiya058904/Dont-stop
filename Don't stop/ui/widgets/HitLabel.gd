extends Label

static var live_count := 0

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
	var tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	if B11Probe.enabled: B11Probe.label_tweens += 1
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self,"scale",Vector2.ONE,0.16).from(Vector2(1.2,1.2))
	tween.tween_property(self,"position:y",position.y - 24,0.65)
	tween.tween_property(self,"modulate:a",0.0,0.22).set_delay(0.55)
	tween.tween_callback(self.queue_free).set_delay(1)

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

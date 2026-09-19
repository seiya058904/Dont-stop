extends Label

func _ready() -> void:
	add_to_group("damage_labels")
	# The arena is 410x230: the theme's default 16px obscures the actor on fast fire.
	add_theme_font_size_override("font_size",8)
	# B11.1 test-only counter (game/diag/B11Probe.gd): damage-number churn rate.
	if B11Probe.enabled: B11Probe.labels_created += 1
	var tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	if B11Probe.enabled: B11Probe.label_tweens += 1
	tween.tween_property(self,"scale",Vector2(1,1),0.2).from(Vector2.ZERO)
	tween.tween_property(self,"position:y",position.y - 50,0.5)
	tween.tween_property(self,"scale",Vector2.ZERO,0.2).set_delay(0.7)
	tween.tween_callback(self.queue_free).set_delay(1)

func setNumber(number):
	# Display precision only: the hit pipeline retains the unrounded value.
	var value := float(number)
	if value != 0.0 and absf(value) < 0.01:
		text = "<0.01" if value > 0 else "−<0.01"
	else:
		text = ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func setColor(color):
	set("theme_override_colors/font_color",color)

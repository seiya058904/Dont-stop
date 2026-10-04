extends CanvasLayer

@onready var toast = $Control/Label
@onready var toast_ui = $Control
@onready var timer = $Control/Timer
@onready var hit_flash = $Sprite2D
var world_effects: CanvasLayer
var toast_tween: Tween
var hit_tween: Tween

func _ready() -> void:
	Utils.canvasLayer = self
	# Each scene owns its flash state, including during a menu handover.
	hit_flash.material = hit_flash.material.duplicate()
	world_effects = CanvasLayer.new()
	world_effects.name = "WorldEffects"
	world_effects.layer = 1
	add_child(world_effects)
	hit_flash.reparent(world_effects)
	var atmosphere = preload("res://ui/Atmosphere.gd").new()
	world_effects.add_child(atmosphere)
	world_effects.move_child(atmosphere,0)
	toast.add_theme_color_override("font_color",Color("f4dfb4"))
	toast.add_theme_stylebox_override("normal",preload("res://ui/GildedTheme.gd").plate(Color("14212be8"),Color("8c7959"),4))
	print("[boot-probe] controlui_ready t=%d" % Time.get_ticks_msec())

func crosshairChange(is_show):
	$TextureRect.visible = is_show

func _on_virtual_joystick_2_on_touch(vector) -> void:
	Utils.player.setGunLookat(vector)

func showToast(msg,time):
	timer.stop()
	if toast_tween and toast_tween.is_valid(): toast_tween.kill()
	timer.start(time)
	if not toast_ui.visible: toast_ui.modulate.a = 0.0
	toast_ui.visible = true
	toast_tween = create_tween()
	toast_tween.tween_property(toast_ui,"modulate:a",1,0.1)
	toast.text = tr(msg)

func _on_timer_timeout():
	if toast_tween and toast_tween.is_valid(): toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_property(toast_ui,"modulate:a",0,0.2)
	toast_tween.tween_callback(self.toast_hide)

func toast_hide():
	toast_ui.visible = false

func hit():
	if hit_tween and hit_tween.is_valid(): hit_tween.kill()
	if Combat.reduced_flash:
		hit_flash.hide()
		return
	hit_flash.visible = true
	hit_tween = create_tween().set_ease(Tween.EASE_IN)
	hit_tween.tween_property(hit_flash.material,"shader_parameter/fade",0,0.2).from(0.01)
	hit_tween.tween_callback(hit_flash.hide)

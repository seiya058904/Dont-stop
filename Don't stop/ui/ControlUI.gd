extends CanvasLayer

@onready var toast = $Control/Label
@onready var toast_ui = $Control
@onready var timer = $Control/Timer

func _ready() -> void:
	Utils.canvasLayer = self
	var atmosphere = preload("res://ui/Atmosphere.gd").new()
	add_child(atmosphere)
	move_child(atmosphere,0)
	toast.add_theme_color_override("font_color",Color("f4dfb4"))
	toast.add_theme_stylebox_override("normal",preload("res://ui/GildedTheme.gd").plate(Color("14212be8"),Color("8c7959"),4))
	print("[boot-probe] controlui_ready t=%d" % Time.get_ticks_msec())

func crosshairChange(is_show):
	$TextureRect.visible = is_show

func _on_virtual_joystick_2_on_touch(vector) -> void:
	Utils.player.setGunLookat(vector)

func showToast(msg,time):
	timer.stop()
	timer.start(time)
	toast_ui.visible = true
	create_tween().tween_property(toast_ui,"modulate:a",1,0.1).from(0)
	toast.text = tr(msg)

func _on_timer_timeout():
	var tween = create_tween()
	tween.tween_property(toast_ui,"modulate:a",0,0.2)
	tween.tween_callback(self.toast_hide)

func toast_hide():
	toast_ui.visible = false

func hit():
	var material_hit = $Sprite2D.material
	$Sprite2D.visible = true
	var tween = create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(material_hit,"shader_parameter/fade",0,0.2).from(0.01)
	tween.tween_callback(func back(): $Sprite2D.visible = false)

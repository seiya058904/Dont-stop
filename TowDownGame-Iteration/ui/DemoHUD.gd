extends Label
var elapsed = 0.0
var root_icon: TextureRect
func _ready():
	position = Vector2(8,174)
	size = Vector2(345,30)
	autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	root_icon=TextureRect.new(); root_icon.texture=load("res://Sprites/All_Icons/Blue Specs.png"); root_icon.position=Vector2(0,-15); root_icon.size=Vector2(12,12); root_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; root_icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; add_child(root_icon)
	add_theme_font_override("font",load("res://fonts/fusion-pixel.otf"))
	add_theme_font_size_override("font_size",6)
	add_theme_color_override("font_shadow_color",Color.BLACK)
	add_theme_constant_override("shadow_offset_x",1)
	add_theme_constant_override("shadow_offset_y",1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Demo.changed.connect(refresh)

func refresh():
	update_text()

func _process(delta):
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0
	update_text()

func update_text():
	text=preload("res://game/config/CombatStatus.gd").display()
	root_icon.visible=is_instance_valid(Utils.player) and (Utils.player.root_remaining>0 or Utils.player.cc_immunity>0)

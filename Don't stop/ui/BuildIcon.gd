extends Button
# One shared treatment for all three build systems. Godot owns popup placement.
var picture: Texture2D
var description = ""
var popup: PanelContainer
var display_picture: Texture2D
## Text-only entries (stat sheet weapon upgrades and talents, by product decision)
## drop the icon entirely instead of scaling it: no icon, no reserved icon width,
## no extra left inset. Every other caller keeps its icon.
var text_only := false
func _ready():
	custom_minimum_size=Vector2(0,27) if text_only else Vector2(25,25)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	display_picture=picture
	var source_image=picture.get_image() if picture else null
	if source_image and source_image.get_used_rect().size!=Vector2i.ZERO:
		var crop=AtlasTexture.new(); crop.atlas=picture; crop.region=source_image.get_used_rect(); display_picture=crop
	if not text_only:
		icon=display_picture; expand_icon=true
		add_theme_constant_override("icon_max_width",18)
	mouse_entered.connect(show_build_tooltip)
	mouse_exited.connect(hide_build_tooltip)
	focus_entered.connect(show_build_tooltip)
	focus_exited.connect(hide_build_tooltip)
	for state in ["normal","hover","pressed","focus"]:
		var style=StyleBoxFlat.new()
		style.bg_color=Color("314955") if state=="normal" else Color("526f78")
		style.border_color=Color("91b9bd"); style.set_border_width_all(1); style.set_content_margin_all(3)
		add_theme_stylebox_override(state,style)
func _make_custom_tooltip(for_text: String) -> Object:
	var box=VBoxContainer.new()
	var preview=TextureRect.new(); preview.texture=display_picture; preview.custom_minimum_size=Vector2(20,20)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; box.add_child(preview)
	var caption=Label.new(); caption.text=for_text; caption.custom_minimum_size.x=145
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_override("font",load("res://fonts/fusion-pixel.otf")); caption.add_theme_font_size_override("font_size",7)
	box.add_child(caption)
	return box
func show_build_tooltip():
	var host=get_parent()
	while host and not host.has_method("render_build"): host=host.get_parent()
	if not host: return
	for old in get_tree().get_nodes_in_group("build_tooltip"):
		old.hide(); old.queue_free()
	popup=PanelContainer.new(); popup.add_to_group("build_tooltip"); popup.z_index=100
	popup.set_meta("source",description); popup.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style=StyleBoxFlat.new(); style.bg_color=Color("10212e"); style.border_color=Color("b9dce0")
	style.set_border_width_all(1); style.set_content_margin_all(4); popup.add_theme_stylebox_override("panel",style)
	var content=_make_custom_tooltip(description); popup.add_child(content)
	for child in content.get_children(): child.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.add_child(popup); place_tooltip.call_deferred()
func place_tooltip():
	if not is_instance_valid(popup): return
	popup.reset_size()
	var bounds=get_viewport_rect().size
	var point=get_global_mouse_position()+Vector2(7,7)
	if point.x+popup.size.x>bounds.x-3: point.x=get_global_mouse_position().x-popup.size.x-7
	if point.y+popup.size.y>bounds.y-3: point.y=get_global_mouse_position().y-popup.size.y-7
	popup.position=Vector2(clampf(point.x,3,maxf(3,bounds.x-popup.size.x-3)),clampf(point.y,3,maxf(3,bounds.y-popup.size.y-3)))
func hide_build_tooltip():
	if is_instance_valid(popup): popup.hide(); popup.queue_free()
	popup=null
func _exit_tree(): hide_build_tooltip()

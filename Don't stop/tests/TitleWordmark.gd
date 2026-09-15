extends Node2D

## Regenerates Sprites/ui/title.png with the correct product name.
##
## The old wordmark had the apostrophe in the wrong place ("Dont'Stop") baked into
## the image, so no config name, browser title or string edit could fix what the
## player actually sees. This draws the title with a font the project already
## ships and saves it over the texture the main menu and the loading screen use.
##
## Run windowed (not --headless): a headless DisplayServer has no rendering, so
## ViewportTexture.get_image() would come back empty.
##   Godot_v4.7.2-stable_win64.exe --path <project> res://tests/TitleWordmark.tscn

const OUT := "res://Sprites/ui/title.png"
const W := 1280
const H := 720
const TEXT := "Don't Stop"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[wordmark] needs a rendering display; run without --headless")
		get_tree().quit(1)
		return
	var view := SubViewport.new()
	view.size = Vector2i(W, H)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var label := Label.new()
	label.text = TEXT
	label.add_theme_font_override("font", load("res://fonts/fusion-pixel.otf"))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	# Sized so the wordmark occupies roughly the same footprint as before.
	label.add_theme_font_size_override("font_size", 220)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var image := view.get_texture().get_image()
	if image == null:
		push_error("[wordmark] no image captured")
		get_tree().quit(1)
		return
	# Trim to the drawn pixels so the menu layout keeps its proportions.
	var used := image.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		image = image.get_region(used)
	var err := image.save_png(ProjectSettings.globalize_path(OUT))
	print("[wordmark] wrote %s (%dx%d) err=%d" % [OUT, image.get_width(), image.get_height(), err])
	get_tree().quit(0 if err == OK else 1)

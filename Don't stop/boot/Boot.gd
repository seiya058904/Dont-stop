extends Control

## Windows launch screen.
##
## Why it exists: the previous build showed the engine's boot splash and then the
## title menu, with the real cost (loading game/map/Main.tscn and its Town/map
## dependencies, plus the warm-up pass) happening with nothing on screen. This
## scene is the project's main scene, so it is the first thing the engine builds:
## it draws its own frame first and only then does the expensive work, in stages,
## always yielding to the renderer between them.
##
## Web does NOT use this scene: the browser shell (web/loader.html) is the loading
## UI there, and the single-threaded web export must not pay for a threaded load.
##
## Honest boundary: nothing can be drawn before the engine itself is up. That
## window is covered by boot_splash (same background colour, project setting), and
## this scene fades in from that exact colour so the hand-off is seamless.

const MAIN_SCENE := "res://game/map/Main.tscn"

## The SceneManager addon builds its dissolve-pattern paths from a string
## ("res://addons/scene_manager/shader_patterns/%s.png"), so the exporter's
## dependency scan cannot see them and the Web build shipped the raw PNGs without
## their imported textures. Every scene transition then failed with "No loader found
## for resource" and left the addon's full-screen blend rectangle in place, which
## swallowed every later click: the player saw the main menu come back and then
## could not press anything - reported as "clicked leave and the picture stopped".
## Referencing them here makes them real dependencies of the export, on every
## platform, without touching the addon.
const TRANSITION_PATTERNS := [
	preload("res://addons/scene_manager/shader_patterns/circle.png"),
	preload("res://addons/scene_manager/shader_patterns/curtains.png"),
	preload("res://addons/scene_manager/shader_patterns/diagonal.png"),
	preload("res://addons/scene_manager/shader_patterns/horizontal.png"),
	preload("res://addons/scene_manager/shader_patterns/radial.png"),
	preload("res://addons/scene_manager/shader_patterns/scribbles.png"),
	preload("res://addons/scene_manager/shader_patterns/squares.png"),
	preload("res://addons/scene_manager/shader_patterns/vertical.png"),
]

var _status: Label
var _fill: TextureRect
var _track: ColorRect
var _activity: ColorRect
var _progress_target := 0.0
var _progress_shown := 0.0
var _sweep := false
var _sweep_time := 0.0
var _boot_ms := 0
## Dev/evidence only: `--boot-capture=<dir>` saves one PNG of the real framebuffer
## at each launch stage, so the launch sequence can be documented without
## screenshotting the desktop. Empty in a normal launch.
var _capture_dir := ""

func _ready() -> void:
	_boot_ms = Time.get_ticks_msec()
	Utils.startup_mark("boot-ready")
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--boot-capture="):
			_capture_dir = arg.substr("--boot-capture=".length())
			DirAccess.make_dir_recursive_absolute(_capture_dir)
	# Belongs to no one: the loading screen must never act on input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# Keeping the transition patterns as a real dependency is the point of the
	# constant above; touch it so the load cannot be optimised away silently.
	print("[boot] transition patterns loaded=%d" % TRANSITION_PATTERNS.size())
	print("[boot] shell drawn at t=%d" % _boot_ms)
	Utils.startup_mark("loading-shell-built")
	if OS.has_feature("web"):
		# The DOM shell already covered the whole engine boot; go straight in.
		# Deferred on purpose: replacing the current scene from inside its own
		# _ready() makes the SceneTree remove a child while it is still adding
		# one, which the engine reports as "Parent node is busy adding/removing
		# children" (and which the Web E2E flags as an unexpected engine error).
		# The stage mark tells the shell that engine bring-up finished and the
		# synchronous scene load below is a real, expected wait.
		Utils.notify_web_boot_stage("scene-prep")
		Utils.startup_mark("scene-prep-start")
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	_run.call_deferred()

## Saves a real screenshot of this viewport (not the desktop) when asked to.
func _capture(name: String) -> void:
	if _capture_dir == "": return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_capture_dir.path_join(name))

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0d0c17")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# Everything below is sized in DESIGN units: the project viewport is only
	# 410x230 and the window stretches it, so a "128 px" icon would be a third of
	# the screen. Sizes here match the browser shell's proportions.
	var icon := TextureRect.new()
	icon.texture = load("res://game-icon.png")
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(_centered(icon))

	var wordmark := TextureRect.new()
	wordmark.texture = load("res://Sprites/ui/title.png")
	wordmark.custom_minimum_size = Vector2(96, 46)
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(_centered(wordmark))

	_status = Label.new()
	_status.text = "正在准备…"
	_status.add_theme_font_override("font", load("res://fonts/fusion-pixel.otf"))
	_status.add_theme_font_size_override("font_size", 8)
	_status.add_theme_color_override("font_color", Color("9d9ab5"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_centered(_status))

	_track = ColorRect.new()
	_track.color = Color("1f1d31")
	_track.custom_minimum_size = Vector2(170, 6)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.clip_contents = true
	var track_wrap := _centered(_track)
	column.add_child(track_wrap)

	var grad := Gradient.new()
	grad.set_color(0, Color("7b6cff"))
	grad.set_color(1, Color("4dc9ff"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 170
	tex.height = 6
	tex.fill_from = Vector2(0, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	_fill = TextureRect.new()
	_fill.texture = tex
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(0, 6)
	_track.add_child(_fill)
	_activity = ColorRect.new()
	_activity.color = Color(0.65, 0.85, 1.0, 0.3)
	_activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_activity.size = Vector2(38, 6)
	_track.add_child(_activity)

func _centered(node: Control) -> Control:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(node)
	return wrap

## progress 0..1, or a negative value for "no measurable progress".
func _set_progress(value: float, text: String) -> void:
	if _status != null and text != "":
		_status.text = text
	if value < 0.0:
		_sweep = true
		return
	# Three real work stages; smoothing never advances beyond completed work.
	_progress_target = maxf(_progress_target, clampf(value, 0.0, 1.0))
	_sweep = value < 1.0
	if value >= 1.0:
		_progress_shown = 1.0
		_fill.size.x = _track.custom_minimum_size.x
		_activity.hide()

func _process(delta: float) -> void:
	if _fill == null or _track == null: return
	_progress_shown = lerpf(_progress_shown, _progress_target, 1.0-exp(-18.0*delta))
	_fill.size.x = _track.custom_minimum_size.x * _progress_shown
	if not _sweep: return
	_sweep_time += delta
	var width: float = _track.custom_minimum_size.x
	var bar := _activity.size.x
	# Activity is separate from measured progress: it cannot imply completion.
	var span := width + bar
	_activity.position.x = fposmod(_sweep_time * span / 1.15, span) - bar

func _run() -> void:
	# Draw the shell before doing anything expensive. Three processed frames with
	# no blocking work in between is the cheapest guarantee that this UI has been
	# presented, so the real work below happens with a visible loading screen -
	# not in front of a frozen boot splash.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("01-loading-shell.png")

	# --- Stage 1: the game scene and everything it drags in (map, town, theme).
	var t0 := Time.get_ticks_msec()
	Utils.startup_mark("scene-load-start")
	_set_progress(0.0, "正在载入游戏场景…")
	var err := ResourceLoader.load_threaded_request(MAIN_SCENE, "PackedScene", true)
	if err != OK:
		_fail("无法开始载入游戏场景 (ResourceLoader error %d)" % err)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress)
	var captured_loading := false
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		progress.clear()
		status = ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress)
		if not progress.is_empty():
			_set_progress(float(progress[0])/3.0, "正在载入游戏场景…")
		if not captured_loading and not progress.is_empty() and float(progress[0]) > 0.2:
			captured_loading = true
			await _capture("02-loading-progress.png")
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("游戏场景载入失败 (status %d)" % status)
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(MAIN_SCENE)
	if packed == null:
		_fail("游戏场景载入失败：资源为空")
		return
	_set_progress(1.0/3.0, "场景资源已就绪")
	Utils.startup_mark("scene-load-100")
	print("[boot] scene loaded in %d ms" % (Time.get_ticks_msec() - t0))

	# --- Stage 2: the warm-up pass. Real work with a real, observable completion
	# signal; it never fires combat audio, deals damage or touches save data.
	var t1 := Time.get_ticks_msec()
	Utils.startup_mark("warmup-start")
	_set_progress(1.0/3.0, "正在准备武器与特效…")
	await _capture("03-warmup.png")
	# Warmup lives as an autoload, so it is looked up by path: `--no-warmup` and
	# TOWDOWN_SKIP_WARMUP free the node, after which the global identifier is gone.
	var warmup := get_node_or_null("/root/Warmup")
	if warmup != null:
		warmup.start()
		# The completed flag, not the progress value, controls the hand-off.
		while is_instance_valid(warmup) and not warmup.is_finished():
			_set_progress((1.0+warmup.progress)/3.0, "正在准备武器与特效…")
			await get_tree().process_frame
	_set_progress(2.0/3.0, "正在呈现主菜单…")
	Utils.startup_mark("warmup-handover")
	print("[boot] warmup finished in %d ms" % (Time.get_ticks_msec() - t1))

	# --- Stage 3: keep the cover alive while the menu is instantiated and drawn.
	# A scene switch normally frees Boot. Move only this cover to a temporary
	# top canvas layer, so 100% can never precede menu construction.
	var tree := get_tree()
	var cover := CanvasLayer.new()
	cover.layer = 128
	tree.root.add_child(cover)
	tree.root.set_meta("boot_overlay_active", true)
	tree.current_scene = null
	reparent(cover)
	Utils.startup_mark("main-scene-handover")
	err = tree.change_scene_to_packed(packed)
	if err != OK:
		_fail("无法打开主菜单 (scene error %d)" % err)
		return
	await tree.scene_changed
	await RenderingServer.frame_post_draw
	_set_progress(1.0, "准备完成")
	Utils.startup_mark("boot-ready-to-handover")
	await _capture("04-ready.png")
	await _fade_out()
	tree.root.remove_meta("boot_overlay_active")
	Utils.startup_mark("menu-first-visible")
	await _capture("05-menu.png")
	cover.queue_free()
	print("[boot] title menu handed over at t=%d ms total" % (Time.get_ticks_msec() - _boot_ms))

func _fade_out() -> void:
	if _status == null: return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	await tween.finished

func _fail(message: String) -> void:
	push_error("[boot] " + message)
	if _status == null: return
	_set_progress(0.0, "启动失败")
	_sweep = false
	_activity.hide()
	var box := Label.new()
	box.text = message + "\n请关闭后重新启动游戏；若反复失败，请核对游戏目录中的可执行文件与同名 .pck 是否完整。"
	box.add_theme_font_override("font", load("res://fonts/fusion-pixel.otf"))
	box.add_theme_font_size_override("font_size", 8)
	box.add_theme_color_override("font_color", Color("ff9d9d"))
	box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.custom_minimum_size = Vector2(420, 0)
	box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_centered(box))

extends Node

## Release warm-up: pay first-use costs (shader/pipeline compile, texture upload,
## material setup) once before the first fight so the first real shot/switch/VFX
## in combat does not hitch. Nodes are drawn for at least one frame, never deal
## damage, play no combat audio and touch no save data, then are freed.
##
## Who drives it:
##   Windows - boot/Boot.gd (the loading scene) calls start() after its own UI is
##             on screen, so the loading animation covers this real work and can
##             report per-scene progress.
##   Web     - no loading scene exists (the DOM shell in web/loader.html is the
##             loading UI), so this autoload starts itself as before and reports
##             completion to the shell through Utils.
## start() is idempotent: a second call can never warm up twice.

signal finished

const WARM_SCENES := [
	"res://game/hero/gpu_particles_2d.tscn",
	"res://game/bullets/BabyBullet.tscn",
	"res://game/bullets/SmpBullet.tscn",
	"res://game/bullets/BulletImpact.tscn",
	"res://game/bullets/BulletShell.tscn",
	"res://game/bullets/BulletSmoke.tscn",
	"res://game/other/FireEffect.tscn",
	"res://ui/widgets/HitLabel.tscn",
]

## Scenes instantiated per drawn frame while staging, so the loading UI keeps
## painting instead of freezing for the whole pass.
const SCENES_PER_FRAME := 3
## The Web export's process_frame await is a browser scheduling boundary, not a
## free operation. The measured warm items are 3-4ms each, so keep batches
## below one 16.6ms frame while avoiding 32 tiny browser hand-offs.
const WEB_BATCH_MAX_ITEMS := 4
const WEB_BATCH_BUDGET_USEC := 8000

var _root: Node2D
var _warm_canvas: CanvasLayer
var _started := false
var _finished := false
## 0.0 - 1.0, only meaningful while start() is running.
var progress := 0.0
var total_scenes := 0

func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.get_environment("TOWDOWN_SKIP_WARMUP") == "1" or "--no-warmup" in args:
		total_scenes = 0
		_finish()
		queue_free()
		return
	total_scenes = WARM_SCENES.size() + Utils.weapon_list.size()
	if OS.has_feature("web"):
		start()

## Runs the pass. Safe to call more than once; only the first call does work.
func start() -> void:
	if _started or _finished:
		return
	_started = true
	# Tell the browser shell this stage has begun, so the gap between "engine up"
	# and "menu ready" is not one anonymous wait it cannot interpret.
	Utils.notify_web_boot_stage("warmup")
	_run()

func is_finished() -> bool:
	return _finished

func _run() -> void:
	print("[warmup] starting total=%d" % total_scenes)
	await get_tree().process_frame
	await get_tree().process_frame
	_root = Node2D.new()
	_root.name = "WarmupRoot"
	# Nearly transparent but still drawn, so GPU pipelines really get compiled.
	_root.modulate = Color(1, 1, 1, 0.05)
	_root.position = Vector2(0, 0)
	_root.z_index = -100
	# The town camera is far from world zero. Draw in screen space, on layer
	# zero so the light's layer mask includes both sprites and primitives.
	_warm_canvas = CanvasLayer.new()
	_warm_canvas.layer = 0
	get_tree().root.add_child(_warm_canvas)
	_warm_canvas.add_child(_root)
	var lit_started := Time.get_ticks_msec()
	_warm_lit_canvas()
	print("[warmup] lit_canvas_ms=%d" % (Time.get_ticks_msec() - lit_started))
	var warmed := 0
	var done := 0
	var batch_started := Time.get_ticks_usec()
	var slowest_ms := 0
	var slowest_label := ""
	for path in WARM_SCENES:
		var item_started := Time.get_ticks_msec()
		warmed += _warm_scene(path)
		var item_ms := Time.get_ticks_msec() - item_started
		if item_ms > slowest_ms:
			slowest_ms = item_ms
			slowest_label = path
		done += 1
		progress = float(done) / maxf(1.0, total_scenes)
		if _warmup_batch_due(done,batch_started):
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
	print("[warmup] effect_scenes_ms=%d" % (Time.get_ticks_msec() - lit_started))
	var weapon_started := Time.get_ticks_msec()
	for id in Utils.weapon_list:
		var item_started := Time.get_ticks_msec()
		warmed += _warm_scene("", Utils.weapon_list[id])
		var item_ms := Time.get_ticks_msec() - item_started
		if item_ms > slowest_ms:
			slowest_ms = item_ms
			slowest_label = "weapon:%s" % id
		done += 1
		progress = float(done) / maxf(1.0, total_scenes)
		if _warmup_batch_due(done,batch_started):
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
	print("[warmup] weapon_scenes_ms=%d" % (Time.get_ticks_msec() - weapon_started))
	print("[warmup] slowest_item=%s ms=%d" % [slowest_label, slowest_ms])
	if warmed > 0:
		print("[warmup] instantiated %d scenes" % warmed)
	# Keep them alive for several drawn frames so particle batches actually
	# spawn, then release cleanly.
	for i in 6:
		await get_tree().process_frame
	_warm_canvas.queue_free()
	# Web evidence: the very first audio voice (player or 2D panner) costs
	# ~100-140 ms in Chromium, which lands exactly on the first shot. Warm the
	# voice pipeline with an inaudible (-80 dB) playback, then stop it.
	if OS.has_feature("web"):
		await _warm_audio()
	progress = 1.0
	_finish()

func _warmup_batch_due(done: int, batch_started: int) -> bool:
	if not OS.has_feature("web"):
		return done % SCENES_PER_FRAME == 0
	return done % WEB_BATCH_MAX_ITEMS == 0 or Time.get_ticks_usec() - batch_started >= WEB_BATCH_BUDGET_USEC

func _finish() -> void:
	if _finished:
		return
	_finished = true
	progress = 1.0
	print("[warmup] finished t=%d" % Time.get_ticks_msec())
	Utils.startup_mark("warmup-finished")
	finished.emit()
	Utils.notify_web_boot_warmup_done()

func _warm_audio() -> void:
	var stream: AudioStream = load("res://audio/bullet/GUNMech_Insert Clip_01.wav")
	if stream == null:
		return
	var flat := AudioStreamPlayer.new()
	flat.stream = stream
	flat.volume_db = -80.0
	add_child(flat)
	var panned := AudioStreamPlayer2D.new()
	panned.stream = stream
	panned.volume_db = -80.0
	add_child(panned)
	flat.play()
	panned.play()
	await get_tree().process_frame
	await get_tree().process_frame
	flat.stop()
	panned.stop()
	flat.queue_free()
	panned.queue_free()
	print("[warmup] audio warmed")

func _warm_scene(path: String, scene: PackedScene = null) -> int:
	if scene == null:
		if not ResourceLoader.exists(path):
			return 0
		scene = load(path)
	if scene == null:
		return 0
	var ins := scene.instantiate()
	if ins == null:
		return 0
	# Keep processing enabled so particles really emit and tweens really run:
	# in Compatibility (Web) the particle pipelines are only compiled when a
	# live particle batch is drawn, which is exactly the first-shot freeze we
	# are paying off here. Nodes are inert gameplay-wise (bullets stay
	# physics-disabled until fire(), nothing can be hit on the title screen).
	ins.position = Vector2.ZERO
	_root.add_child(ins)
	_wake_particles(ins)
	return 1

func _wake_particles(node: Node) -> void:
	if node is GPUParticles2D:
		var p := node as GPUParticles2D
		p.emitting = true
		p.restart()
	for child in node.get_children():
		_wake_particles(child)

func _warm_lit_canvas() -> void:
	# The production Monster2 scene is already preloaded by Town/M5Content. Do not
	# instantiate a full CharacterBody2D here just to borrow its SpriteFrames: that
	# creates its script, collision, navigation obstacle and ready path during the
	# Web startup pass. Build the same six-frame run animation from the same
	# spritesheet instead, so the first animated-sprite + hit-flash draw is still
	# exercised without duplicating a gameplay actor.
	var frames := SpriteFrames.new()
	frames.add_animation("run")
	frames.set_animation_loop("run",true)
	frames.set_animation_speed("run",15.0)
	var monster_texture: Texture2D = load("res://game/monster/Monster 2/50x31 Monster 2 spritesheet without shadows.png")
	for frame_index in 6:
		var atlas := AtlasTexture.new()
		atlas.atlas = monster_texture
		atlas.region = Rect2(frame_index*50,31,50,31)
		frames.add_frame("run",atlas)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	var material := ShaderMaterial.new()
	material.shader = load("res://shader/HitFlash.gdshader")
	material.set_shader_parameter("enchantment_tier",2.0)
	sprite.material = material
	sprite.position = Vector2(32,32)
	_root.add_child(sprite)
	sprite.play("run")
	_root.add_child(load("res://game/diag/WarmupCanvas.gd").new())
	var light := PointLight2D.new()
	light.texture = load("res://Sprites/light2.png")
	light.position = Vector2(32,32)
	_root.add_child(light)
	# The standalone production particle scene is warmed by WARM_SCENES below.
	# This second emitter covers the Hero dash texture/material path without
	# instantiating the full Hero (which would also build its input, collision and
	# reward nodes during startup).
	var dash_particles := GPUParticles2D.new()
	dash_particles.amount = 50
	dash_particles.lifetime = 0.5
	dash_particles.position = Vector2(32,32)
	dash_particles.texture = load("res://game/bullets/assets/lights1.png")
	var dash_material := ParticleProcessMaterial.new()
	dash_material.gravity = Vector3.ZERO
	dash_material.initial_velocity_min = 100.0
	dash_material.initial_velocity_max = 100.0
	dash_particles.process_material = dash_material
	_root.add_child(dash_particles)
	dash_particles.emitting = true
	dash_particles.restart()

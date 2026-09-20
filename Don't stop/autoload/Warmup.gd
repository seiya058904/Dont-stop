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
	_warm_lit_canvas()
	var warmed := 0
	var done := 0
	for path in WARM_SCENES:
		warmed += _warm_scene(path)
		done += 1
		progress = float(done) / maxf(1.0, total_scenes)
		if done % SCENES_PER_FRAME == 0:
			await get_tree().process_frame
	for id in Utils.weapon_list:
		warmed += _warm_scene("", Utils.weapon_list[id])
		done += 1
		progress = float(done) / maxf(1.0, total_scenes)
		if done % SCENES_PER_FRAME == 0:
			await get_tree().process_frame
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

func _finish() -> void:
	if _finished:
		return
	_finished = true
	progress = 1.0
	print("[warmup] finished t=%d" % Time.get_ticks_msec())
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
	var scene = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	var frames: SpriteFrames = scene.get_node("body/AnimatedSprite2D").sprite_frames
	scene.free()
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
	var hero = load("res://game/hero/Hero.tscn").instantiate()
	for path in ["body/DashParticles2D","GPUParticles2D"]:
		var particles = hero.get_node(path).duplicate()
		particles.position = Vector2(32,32)
		_root.add_child(particles)
		particles.emitting = true
		particles.restart()
	hero.free()

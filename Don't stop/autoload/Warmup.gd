extends Node

## Release warm-up: pay first-use costs (shader/pipeline compile, texture upload,
## material setup) once at the title screen so the first real shot/switch/VFX in
## combat does not hitch. Nodes are drawn for at least one frame, never deal
## damage, play no combat audio and touch no save data, then are freed.

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

var _root: Node2D

func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.get_environment("TOWDOWN_SKIP_WARMUP") == "1" or "--no-warmup" in args:
		queue_free()
		return
	_run.call_deferred()

func _run() -> void:
	print("[warmup] starting")
	await get_tree().process_frame
	await get_tree().process_frame
	_root = Node2D.new()
	_root.name = "WarmupRoot"
	# Nearly transparent but still drawn, so GPU pipelines really get compiled.
	_root.modulate = Color(1, 1, 1, 0.004)
	_root.position = Vector2(0, 0)
	_root.z_index = -100
	get_tree().root.add_child(_root)
	var warmed := 0
	for path in WARM_SCENES:
		warmed += _warm_scene(path)
	for id in Utils.weapon_list:
		warmed += _warm_scene("", Utils.weapon_list[id])
	if warmed > 0:
		print("[warmup] instantiated %d scenes" % warmed)
	# Keep them alive for several drawn frames so particle batches actually
	# spawn, then release cleanly.
	for i in 6:
		await get_tree().process_frame
	_root.queue_free()
	# Web evidence: the very first audio voice (player or 2D panner) costs
	# ~100-140 ms in Chromium, which lands exactly on the first shot. Warm the
	# voice pipeline with an inaudible (-80 dB) playback, then stop it.
	if OS.has_feature("web"):
		await _warm_audio()

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

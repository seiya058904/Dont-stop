extends Node

var owner_ref: WeakRef
var heading = Vector2.RIGHT
var kind = "fan"
var count = 9
var waves = 2
var interval = 0.22
var speed = 135.0
var spread = 0.8
var shift = 0.08
var elapsed = 0.0
var next_wave = 0
var epoch = 0

func _ready():
	add_to_group("combat_transient")
	epoch = LevelServer.epoch

func _physics_process(delta):
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor) or actor.is_die or epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		queue_free(); return
	elapsed += delta
	if elapsed < next_wave*interval: return
	var emitted = 0
	for i in count:
		var angle = lerpf(-spread,spread,float(i)/maxi(1,count-1))
		if kind == "ring":
			angle = TAU*i/count
			# Three vacant angular slots form a deterministic, learnable escape gap.
			if i in [0,1,count-1]: continue
		angle += shift*next_wave
		if actor.shot(heading.rotated(angle),speed,0.18,false): emitted += 1
	actor.remember("barrage_wave")
	actor.actions["barrage_projectiles"] = actor.actions.get("barrage_projectiles",0)+emitted
	next_wave += 1
	if next_wave >= waves: queue_free()

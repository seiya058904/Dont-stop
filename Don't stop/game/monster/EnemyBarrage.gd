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
var next_due = 0.0
var epoch = 0
## Ink and control payload for the whole pattern, so a control volley is visually a control
## volley (purple, waveform pellets) rather than indistinct orange pellets.
var style = "projectile"
var control = 0.0
var deferred_seconds = 0.0

func angles() -> Array:
	var result = []
	for i in count:
		var angle = lerpf(-spread,spread,float(i)/maxi(1,count-1))
		if kind == "ring":
			angle = TAU*i/count
			# A 64px chord at R=80 leaves 40px beyond the combined hit threshold.
			# Gap width is angular, so denser rings never shrink it to three slots.
			if absf(wrapf(angle,-PI,PI)) < 0.42: continue
		result.append(angle+shift*next_wave)
	return result

func _ready():
	add_to_group("combat_transient")
	epoch = LevelServer.epoch

func _physics_process(delta):
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor) or actor.is_die or epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		queue_free(); return
	elapsed += delta
	if elapsed < next_due: return
	var directions = angles()
	var live = get_tree().get_nodes_in_group("enemy_projectiles").size()
	# One synchronous wave is atomic: no await or competing spawn in this loop.
	# Keep the measured 180 ceiling until higher capacity has been demonstrated.
	if live+directions.size() > 180:
		deferred_seconds += delta
		actor.remember("barrage_deferred")
		if deferred_seconds > 4.0:
			actor.remember("barrage_cancelled_capacity"); queue_free()
		return
	deferred_seconds = 0.0
	actor.actions["barrage_requested"] = actor.actions.get("barrage_requested",0)+directions.size()
	var emitted = 0
	for angle in directions:
		if actor.shot(heading.rotated(angle),speed,0.18,false,style,control): emitted += 1
	actor.remember("barrage_wave")
	actor.actions["barrage_projectiles"] = actor.actions.get("barrage_projectiles",0)+emitted
	next_wave += 1
	next_due = elapsed+interval
	if next_wave >= waves: queue_free()

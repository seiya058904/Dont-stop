extends Node2D

## B19: a small, owner-bound pressure stream. It is deliberately separate from the
## finite EnemyBarrage so active attack choices cannot accidentally pause or restart it.
var owner_ref: WeakRef
var epoch := -1
var elapsed := 0.0
var next_due := 0.0
var telegraph := 0.55
var interval := 2.4
var count := 8
var speed := 125.0
var damage := 0.16
var style := "projectile"
var bounces := 0
var deferred_seconds := 0.0
var wave_pending := false

const BOSS_SPECS := {
	"B01":{"telegraph":0.55,"interval":2.40,"count":8,"speed":125.0,"damage":0.16,"style":"projectile","bounces":0},
	"B02":{"telegraph":0.60,"interval":2.65,"count":10,"speed":118.0,"damage":0.15,"style":"poison","bounces":0},
	"B03":{"telegraph":0.50,"interval":2.20,"count":8,"speed":142.0,"damage":0.14,"style":"laser","bounces":1},
	"B04":{"telegraph":0.65,"interval":2.80,"count":7,"speed":126.0,"damage":0.17,"style":"ricochet","bounces":1}
}
const ELITE_SPECS := {
	"E10":{"telegraph":0.48,"interval":3.10,"count":4,"speed":116.0,"damage":0.12,"style":"laser","bounces":0},
	"E14":{"telegraph":0.52,"interval":3.30,"count":4,"speed":110.0,"damage":0.12,"style":"laser","bounces":0}
}

func _ready():
	epoch = LevelServer.epoch
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor):
		queue_free(); return
	var spec = BOSS_SPECS.get(actor.role,ELITE_SPECS.get(actor.role,{}))
	if spec.is_empty():
		queue_free(); return
	telegraph = float(spec.telegraph)
	interval = float(spec.interval)
	count = int(spec.count)
	speed = float(spec.speed)
	damage = float(spec.damage)
	style = str(spec.style)
	bounces = int(spec.bounces)
	next_due = telegraph
	add_to_group("combat_transient")
	actor.remember("continuous_barrage_attached")
	queue_redraw()

func _b04_safe_zone_active(actor) -> bool:
	if actor.role != "B04": return false
	for ultimate in get_tree().get_nodes_in_group("boss_ultimate"):
		if not is_instance_valid(ultimate) or ultimate.is_queued_for_deletion(): continue
		if ultimate.get("role") == "B04": return true
	return false

func _paused(actor) -> bool:
	# The clock freezes during a readability/safety window; it never catches up with
	# several synchronous waves after the window ends.
	if LevelServer.state != "COMBAT": return true
	if actor.phase in ["spawn","transition","pause"]: return true
	if _b04_safe_zone_active(actor):
		actor.remember("continuous_barrage_paused_safe_zone")
		return true
	return false

func _directions() -> Array:
	var result: Array = []
	var rotation = fmod(elapsed*0.22,TAU)
	for i in count:
		result.append(Vector2.RIGHT.rotated(rotation+TAU*float(i)/float(count)))
	return result

func _physics_process(delta):
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor) or actor.is_die or epoch != LevelServer.epoch:
		queue_free(); return
	if _paused(actor):
		queue_redraw(); return
	elapsed += delta
	queue_redraw()
	if elapsed < next_due: return
	if not wave_pending:
		wave_pending = true
		actor.actions["continuous_barrage_planned"] = actor.actions.get("continuous_barrage_planned",0)+count

	var directions = _directions()
	var shot_script = preload("res://game/monster/EnemyShot.gd")
	var live = shot_script.live_count
	if live+directions.size() > shot_script.capacity_limit:
		deferred_seconds += delta
		actor.remember("continuous_barrage_deferred")
		# A continuous stream must skip an over-cap tick, not accumulate a burst.
		if deferred_seconds >= 1.5:
			actor.remember("continuous_barrage_capacity_skip")
			actor.actions["continuous_barrage_cancelled"] = actor.actions.get("continuous_barrage_cancelled",0)+count
			wave_pending = false
			deferred_seconds = 0.0
			next_due = elapsed+interval
		return
	deferred_seconds = 0.0
	var emitted := 0
	actor.actions["continuous_barrage_requested"] = actor.actions.get("continuous_barrage_requested",0)+directions.size()
	for direction in directions:
		if actor.shot(direction,speed,damage,false,style,bounces) != null: emitted += 1
	actor.actions["continuous_barrage_emitted"] = actor.actions.get("continuous_barrage_emitted",0)+emitted
	actor.remember("continuous_barrage_wave")
	wave_pending = false
	next_due = elapsed+interval

func _draw():
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor) or actor.is_die: return
	if elapsed >= telegraph: return
	var progress = clampf(elapsed/telegraph,0.0,1.0)
	var color = Color(0.95,0.65,0.28,0.65) if actor.role != "B04" else Color(0.72,0.42,1.0,0.72)
	# Small source telegraph: readable at the owner centre and cheaper than a child
	# particle system. The actual pellets appear only on the completed edge.
	draw_arc(Vector2.ZERO,8.0+progress*5.0,0,TAU,12,color,1.2,true)
	for i in 4:
		var direction = Vector2.RIGHT.rotated(i*PI/2)
		draw_line(direction*(10.0+progress*3.0),direction*(14.0+progress*8.0),color,1.5,true)

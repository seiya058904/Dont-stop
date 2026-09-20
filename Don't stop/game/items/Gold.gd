extends "res://game/items/BaseItem.gd"

var collected := false
var attracting := false
var speed := 0.0
var epoch := -1
var scan_clock := 0.0
static var active_coins := 0
const ACTIVE_LIMIT := 64

func _ready():
	epoch = LevelServer.epoch
	scan_clock = float(get_instance_id()%12)/60.0
	add_to_group("combat_transient")
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self,"scale",Vector2.ONE,0.3).from(Vector2.ZERO)

func _exit_tree():
	stop_attraction()

func stop_attraction():
	if attracting: active_coins -= 1
	attracting = false
	speed = 0.0

func _physics_process(delta):
	if collected: return
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		queue_free(); return
	if not is_instance_valid(Utils.player) or Utils.player.is_dead: stop_attraction(); return
	var target = Utils.player.global_position
	if not attracting:
		scan_clock -= delta
		if scan_clock > 0: return
		scan_clock += 0.2
		var radius = RewardServer.coin_radius()
		if radius <= 0 or active_coins >= ACTIVE_LIMIT or global_position.distance_squared_to(target) > radius*radius: return
		if not Combat.clear_line(global_position,target): return
		attracting = true
		active_coins += 1
	# Losing line of sight stops flight; no pathfinding or wall crossing.
	if not Combat.clear_line(global_position,target): stop_attraction(); return
	speed = minf(360.0,speed+900.0*delta)
	global_position = global_position.move_toward(target,speed*delta)
	if global_position.distance_squared_to(target) <= 36.0:
		_on_area_2d_body_entered(Utils.player)

func _on_area_2d_body_entered(body):
	if not body is Player or collected or body.is_dead or get_tree().paused: return
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT" or not Combat.clear_line(global_position,body.global_position): return
	collected = true
	stop_attraction()
	if giveCallBack: giveCallBack.call()
	RewardServer.collect_gold()
	queue_free()

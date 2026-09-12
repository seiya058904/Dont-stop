extends "res://game/items/BaseItem.gd"
#金币
var collected = false
var magnet_rank = -1
var magnet_radius_squared = 0.0
func _physics_process(_delta):
	var rank = Demo.rank("T09")
	if rank != magnet_rank:
		magnet_rank = rank
		magnet_radius_squared = pow(20*(1.0+DemoConfig.talent_value("T09",rank)),2) if rank > 0 else 0.0
	if magnet_rank > 0 and is_instance_valid(Utils.player) and global_position.distance_squared_to(Utils.player.global_position) <= magnet_radius_squared and Combat.clear_line(global_position,Utils.player.global_position):
		_on_area_2d_body_entered(Utils.player)
func _ready():
	add_to_group("combat_transient")
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self,"scale",Vector2(1,1),0.3).from(Vector2.ZERO)

func _on_area_2d_body_entered(body):
	if body is Player and not collected and LevelServer.state == "COMBAT" and Combat.clear_line(global_position,body.global_position):
		collected = true
		set_physics_process(false)
		if giveCallBack:
			giveCallBack.call()
		PlayerData.gold += 1
		var tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_parallel(true)
		tween.tween_property(self,"position:y",position.y - 20,0.3)
		tween.tween_property(self,"modulate:a",0.0,0.3)
		tween.tween_callback(self.queue_free).set_delay(0.3)
		Utils.showHitLabel("+1",body)

extends Node2D

var hp = 0
var collected = false
func _physics_process(_delta):
	if PlayerData.player_hp < PlayerData.player_hp_max and RewardServer.pickup_bonus() > 0 and is_instance_valid(Utils.player) and global_position.distance_to(Utils.player.global_position) <= 20*(1.0+RewardServer.pickup_bonus()) and Combat.clear_line(global_position,Utils.player.global_position):
		_on_area_2d_body_entered(Utils.player)

func _ready() -> void:
	add_to_group("combat_transient")
	global_position += Vector2(randf_range(-5,5),randf_range(-5,5))

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is Player and not body.is_dead and not collected and PlayerData.player_hp < PlayerData.player_hp_max and LevelServer.state == "COMBAT" and not get_tree().paused and Combat.clear_line(global_position,body.global_position):
		collected = true
		var before = PlayerData.player_hp
		PlayerData.addPlayerHp(hp)
		Utils.showHitLabelMore("+%.2f"%(PlayerData.player_hp-before),body,Vector2(0,2),Color.SPRING_GREEN)
		queue_free()

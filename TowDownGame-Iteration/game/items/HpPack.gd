extends Node2D

var hp = 0
var collected = false
func _physics_process(_delta):
	if Demo.rank("T09") > 0 and is_instance_valid(Utils.player) and global_position.distance_to(Utils.player.global_position) <= 20*(1.0+DemoConfig.talent_value("T09",Demo.rank("T09"))) and Combat.clear_line(global_position,Utils.player.global_position):
		_on_area_2d_body_entered(Utils.player)

func _ready() -> void:
	add_to_group("combat_transient")
	global_position += Vector2(randf_range(-5,5),randf_range(-5,5))

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is Player and not collected and Combat.clear_line(global_position,body.global_position):
		collected = true
		PlayerData.addPlayerHp(hp)
		Utils.showHitLabelMore("+%s"%hp,body,Vector2(0,2),Color.SPRING_GREEN)
		queue_free()

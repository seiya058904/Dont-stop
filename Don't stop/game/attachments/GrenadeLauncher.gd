extends "res://game/attachments/BaseAttachment.gd"

var can_shoot = true

const pre = preload("res://game/other/Grenade.tscn")

func _unhandled_input(_event: InputEvent) -> void:
	# B16: legacy attachment scenes cannot bypass the automatic A9 budget.
	pass

func _on_timer_timeout() -> void:
	can_shoot = true

func openFire():
	$AudioStreamPlayer2D.play()
	var ins = pre.instantiate()
	ins.global_position = gun.global_position
	get_tree().root.add_child(ins)
	ins.launch(Utils.get_aim_world_position())

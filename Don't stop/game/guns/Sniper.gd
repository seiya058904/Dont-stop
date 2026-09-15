extends "res://game/guns/BaseGun.gd"


func _process(delta):
	super._process(delta)
	queue_redraw()

func _draw():
	var point = $GunTip.position + Vector2($GunTip.global_position.distance_to(Utils.get_aim_world_position()),0)
	draw_line($GunTip.position+Vector2(5,0),point-Vector2(5,0),Color.WHITE,1)

func _shoot():
	super._shoot()
	var mouse_pos = Utils.get_aim_world_position()
	var direction = (mouse_pos - gun_tip.global_position).normalized()
	gun_tip.rotation = direction.angle()
	var b = bullet_scene.instantiate()
	b.setOnwer(player)
	get_tree().root.add_child(b)
	b.position = gun_tip.global_position
	b.rotation = gun_tip.rotation
	fire(b)

func _shootAnim():
	if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
	super._shootAnim()
	play_shot_feedback(timer.wait_time*effective.get("recovery",1.0))

func _on_timer_timeout():
	can_shoot = true

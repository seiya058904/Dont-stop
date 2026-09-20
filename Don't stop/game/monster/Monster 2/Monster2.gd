extends "res://game/monster/BaseMonster.gd"

var area_player = null
var _awaiting_attack_animation := false

func _ready():
	super._ready()
	anim.play("idle")
	anim.animation_finished.connect(_finish_attack_animation)

func _on_area_2d_body_entered(body):
	if body is Player && !is_die:
		area_player = body
		is_atk = true
		$AtkTimer.start()

func onAtk():
	if is_die:
		return
	_awaiting_attack_animation = true
	anim.play("atk")

func _finish_attack_animation():
	if not _awaiting_attack_animation: return
	_awaiting_attack_animation = false
	if not is_die: anim.play("idle")

func _on_animated_sprite_2d_frame_changed():
	if anim.animation == "atk" && anim.frame == 5 && area_player != null && !is_die:
		area_player.onHit(hurt,self,1.0,"contact")


func _on_area_2d_body_exited(body):
	if body is Player:
		is_atk = false
		area_player = null

func _on_atk_timer_timeout():
	onAtk()

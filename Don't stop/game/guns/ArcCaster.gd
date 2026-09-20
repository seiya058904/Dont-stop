extends "res://game/guns/AlienRifle.gd"

func _ready():
	super._ready()
	tags = ["chain","energy"]

func _shoot():
	if not is_use or player.is_dead or get_tree().paused or is_reloading or bullets_count <= 0: return
	var context = shot_context()
	bullets_count -= 1
	Combat.arc(self,gun_tip.global_position,direction,context)
	audio.play()
	_shootAnim()

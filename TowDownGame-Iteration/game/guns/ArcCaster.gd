extends "res://game/guns/AlienRifle.gd"

func _ready():
	super._ready()
	tags = ["chain","energy"]

func _shoot():
	if bullets_count <= 0: return
	bullets_count -= 1
	Combat.arc(self,gun_tip.global_position,direction)
	audio.play()
	_shootAnim()

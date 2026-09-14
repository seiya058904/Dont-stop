extends "res://game/guns/AlienRifle.gd"

func _ready():
	super._ready()
	tags = ["projectile","energy","explosive"]

func _shoot():
	var bullet = bullet_scene.instantiate()
	bullet.set_script(load("res://game/bullets/PlasmaBullet.gd"))
	bullet.setOnwer(player)
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = gun_tip.global_position
	bullet.rotation = direction.angle()
	fire(bullet)
	_shootAnim()

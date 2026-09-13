extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(124)
	LevelServer.town.depart(20,true); LevelServer.timerStop(); await clean()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
	play_view.size = Vector2i(960,720)
	var center = LevelServer.town.arena.global_position
	var camera = Camera2D.new(); play_view.add_child(camera); camera.global_position = center; camera.zoom = Vector2(1.5,1.5); camera.make_current()
	for role in ["B01","B02","B03"]:
		LevelServer.state = "COMBAT"
		Utils.player.global_position = center+Vector2(90,25)
		var actor = M5Content.spawn(role,LevelServer.town.monster_root,center-Vector2(55,15))
		actor.set_physics_process(false); actor.phase_two = true; actor.phase_label.text = M5Content.definition(role).name+" · II"
		actor.attack_index = 0 if role=="B02" else 2
		actor.choose_attack(); await wait(actor.phase_time)
		actor.perform_attack(); await wait(0.65)
		RenderingServer.force_draw(false); await RenderingServer.frame_post_draw
		play_view.get_texture().get_image().save_png("res://docs/iteration/evidence/m8/m9-barrage-"+role+".png")
		print("M9_BARRAGE_VISUAL ",role," live=",get_tree().get_nodes_in_group("enemy_projectiles").size())
		await clean()
	LevelServer.return_to_camp(); dismiss(); await wait(0.3)
	await Demo.quit_game()

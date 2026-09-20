extends "res://tests/B8Runtime.gd"

func _ready():
	await boot(); configure(116); dismiss()
	LevelServer.timer.stop(); LevelServer.level=40; LevelServer.epoch+=1
	LevelServer.town.prepare_region("R8"); await wait(0.2)
	LevelServer.state="COMBAT"
	await visual_ready(Vector2i(410,230)); recenter()
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	PlayerData.player_hp_max=10000; PlayerData.player_hp=10000
	var output="res://evidence/visual-upgrade-20260919/b15-meteor"
	for arg in OS.get_cmdline_user_args():
		if arg=="--final": output+="-final"
	DirAccess.make_dir_recursive_absolute(output)
	for fog in [false,true]:
		ArenaVisibility.apply_stage(40 if fog else 1)
		var hazard=StageHazard.new(); hazard.kind="meteor"
		hazard.at=Utils.player.global_position+Vector2(70,0); hazard.warning=1.5; hazard.active_time=0.35
		get_tree().current_scene.add_child(hazard)
		for frame in 18:
			await wait(0.1); await settle_render()
			play_view.get_texture().get_image().save_png(output+"/%s-%02d.png"%[str(fog),frame])
		var shock=StageHazard.new(); shock.kind="shock"; shock.at=Utils.player.global_position+Vector2(-100,50)
		shock.direction=Vector2.RIGHT; shock.sweep=46; shock.warning=0.9; shock.active_time=1.5; shock.damage=0
		get_tree().current_scene.add_child(shock)
		for frame in 10:
			await wait(0.15); await settle_render()
			play_view.get_texture().get_image().save_png(output+"/shock-%s-%02d.png"%[str(fog),frame])
		await clean()
	print("B15_METEOR_VISUAL done")
	get_tree().quit()

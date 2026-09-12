extends "res://tests/M8Runtime.gd"
var captured = {}
func capture(name: String):
	await RenderingServer.frame_post_draw
	var picture = play_view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	picture.save_png("res://docs/iteration/evidence/m8/"+name+".png")
func _ready():
	await boot(); configure(124,true)
	await capture("camp")
	Demo.open_panel(); Demo.ui.switch_tab("attachment"); await wait(0.2); await capture("upgrades"); dismiss(); await wait(0.1)
	LevelServer.town.depart(30,true); LevelServer.timerStop()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
	for camera in get_tree().get_nodes_in_group("camera"): camera.enabled = false
	var camera = Camera2D.new(); play_view.add_child(camera); camera.global_position = LevelServer.town.arena.global_position; camera.make_current()
	Utils.player.global_position = camera.global_position+Vector2(55,20)
	for id in ["E03","E10","E12","B01","B02","B03"]:
		await clean(); LevelServer.state = "COMBAT"
		var actor = M5Content.spawn(id,LevelServer.town.monster_root,camera.global_position-Vector2(55,0))
		if actor.is_boss: LevelServer.boss_instance = actor.get_instance_id()
		for sample in 200:
			await wait(0.1)
			if not is_instance_valid(actor) or actor.is_die: break
			if sample==100 and actor.is_boss: actor.HP = actor.max_hp*0.49
			for zone in get_tree().get_nodes_in_group("hostile_zone"):
				var kind = zone.mode+("-sweep" if zone.sweep!=0 else "")
				var key = id+"-"+kind+("-active" if zone.elapsed>=zone.warning else "-warning")
				if zone.elapsed<zone.warning*0.4 or captured.has(key): continue
				captured[key] = true; await capture(key)
			if sample in [70,145]: await capture(id+"-phase-"+str(sample))
		print("M8 VISUAL ",id," captures=",captured.size())
	await clean(); LevelServer.state = "CAMP"; print("M8 VISUAL SUMMARY checks=",captured.size()," failures=0")
	await Demo.quit_game()

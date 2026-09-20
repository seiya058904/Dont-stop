extends "res://tests/B8Runtime.gd"

func _ready():
	await boot(); configure(112); dismiss()
	var rows=[]
	var output="res://evidence/visual-upgrade-20260919/b15-boss-phases"
	DirAccess.make_dir_recursive_absolute(output)
	for stage in [10,20,30,40]:
		LevelServer.return_to_camp(); await clean(); dismiss()
		if Utils.player.is_dead: PlayerData.resurrectPlayer(10000,100)
		check(LevelServer.town.depart(stage,true),"Boss phase fixture depart %d"%stage)
		await visual_ready(Vector2i(410,230)); recenter()
		PlayerData.player_hp_max=10000; PlayerData.player_hp=10000
		Utils.player.set_physics_process(false); Utils.player.set_process(false)
		var boss=instance_from_id(LevelServer.boss_instance)
		check(is_instance_valid(boss) and boss.max_hp==M5Content.BOSSES[boss.role].hp,"authored Boss HP %d"%stage)
		for phase_index in [1,2,3]:
			# Controlled health setup to inspect each real phase; no claim of a player clear.
			if phase_index==2: boss.HP=boss.max_hp*0.60
			if phase_index==3: boss.HP=boss.max_hp*0.25
			await wait(3.5); await settle_render()
			check((phase_index==1 and not boss.phase_two) or (phase_index==2 and boss.phase_two) or (phase_index==3 and boss.phase_three),"real phase transition %d/%d"%[stage,phase_index])
			play_view.get_texture().get_image().save_png(output+"/%d-%d.png"%[stage,phase_index])
			rows.append({"stage":stage,"phase":phase_index,"actions":boss.actions.duplicate(),"method":"phase smoke with controlled Boss HP and durable stationary observer; not normal-HP clear"})
		if stage==40:
			var meteor=StageHazard.new(); meteor.kind="meteor"; meteor.at=Utils.player.global_position+Vector2(80,0)
			get_tree().current_scene.add_child(meteor)
			var ultimate=load("res://game/monster/BossUltimate.gd").new(); ultimate.role="B04"; ultimate.owner_ref=weakref(boss)
			get_tree().current_scene.add_child(ultimate)
			check(meteor.is_queued_for_deletion(),"B04 sole safe zone cancels outstanding environmental meteor")
	var file=FileAccess.open(output+"/result.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("B15 BOSS checks=",checks," failures=",failures)
	await clean(); get_tree().quit(1 if failures else 0)

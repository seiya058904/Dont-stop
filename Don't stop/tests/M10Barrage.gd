extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(124)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin+Vector2(200,0)
	PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000
	var actors = Node2D.new(); add_child(actors)
	var rows = []
	var pressures = []
	var observer = func(raw,_applied,_boss): pressures.append(raw)
	Utils.player.incoming_hit.connect(observer)
	for role in ["B01","B02","B03","E10","E11"]:
		for second_phase in [false,true]:
			for index in [0,1,2]:
				LevelServer.state = "COMBAT"
				var actor = M5Content.spawn(role,actors,origin)
				actor.set_physics_process(false)
				actor.phase_two = second_phase
				actor.ultimate_cooldown = 999
				actor.is_elite = true
				actor.attack_index = index
				actor.choose_attack()
				var warning = actor.phase_time
				await wait(warning)
				actor.perform_attack()
				var started = Time.get_ticks_msec()
				var peak = 0
				var frames = []
				while Time.get_ticks_msec()-started<1700:
					var bullets = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/monster/EnemyShot.gd"))
					peak = maxi(peak,bullets.size())
					frames.append({"ms":Time.get_ticks_msec()-started,"active":bullets.size()})
					await wait(0.05)
				var row = {"role":role,"phase_two":second_phase,"attack":actor.attack_kind,"warning":warning,"shots":actor.actions.get("shot",0),"projectile_peak":peak,"samples":frames,"fixture":"forced attack selection and phase, production warning/action/projectile execution; not survival acceptance"}
				if not "baseline" in OS.get_cmdline_user_args():
					if role=="B01" and actor.attack_kind=="slam": check(row.shots>=9,"B01 slam ring density")
					if role=="B02" and actor.attack_kind in ["pulse","brood"]: check(row.shots>=30,"B02 sustained barrage density")
					if role=="B03" and actor.attack_kind=="burst": check(row.shots>=18,"B03 layered fan density")
				rows.append(row); print("M10_PATTERN ",JSON.stringify(row))
				await clean()
				DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/m10")
				var suffix = "baseline" if "baseline" in OS.get_cmdline_user_args() else "final"
				var file = FileAccess.open("res://docs/iteration/evidence/m10/barrage-"+suffix+".json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	Utils.player.incoming_hit.disconnect(observer)
	if not "baseline" in OS.get_cmdline_user_args(): check(pressures.any(func(value): return value>0 and value<1),"real incoming barrage pressure remains fractional")
	print("M10_BARRAGE checks=",checks," failures=",failures," incoming_pressure=",pressures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	Demo.owned_global_upgrades.clear()
	Demo.talents.clear()
	Demo.refresh()
	var raw = "raw" in OS.get_cmdline_user_args()
	var rows = []
	for key in Utils.weapon_list:
		var id = int(key)
		if Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--id=")) and not Array(OS.get_cmdline_user_args()).has("--id="+str(id)): continue
		configure(id,false)
		var gun = Utils.player.gun
		for scenario in ["single","crowd","boss"]:
			if Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--scenario=")) and not Array(OS.get_cmdline_user_args()).has("--scenario="+scenario): continue
			seed(909)
			# Six crowd kills must not level later samples into a stronger build.
			PlayerData.player_level = 1
			PlayerData.player_exp = 0
			Demo.refresh()
			gun.updateGun()
			if raw:
				gun.effective.damage = gun.base_stats.damage
				gun.effective.crit = 0.0
			gun.bullets_count = gun.bullets_max_count
			PlayerData.reserve_magazines = 1000
			LevelServer.state = "COMBAT"
			var targets = []
			for i in (6 if scenario == "crowd" else 1):
				var target = enemy(origin+Vector2(40+(i/3)*20,(i%3-1)*14+8) if scenario == "crowd" else origin+Vector2(50,8),100000)
				if scenario == "crowd": target.HP = 30
				if scenario == "boss": target.is_boss = true
				target.training = false
				target.knockback_def = 100000
				target.set_physics_process(false)
				target.set_meta("initial_hp",target.HP)
				targets.append(target)
			await wait(0.08)
			var start = Time.get_ticks_msec()
			var burst = {}
			var previous_ms = start
			var reload_seconds = 0.0
			var reload_count = 0
			var was_reloading = false
			var clear_seconds = -1.0
			shots_fired = 0
			while Time.get_ticks_msec()-start < (180000 if scenario == "crowd" else 15000):
				var now = Time.get_ticks_msec()
				var delta = (now-previous_ms)/1000.0
				previous_ms = now
				if gun.is_reloading: reload_seconds += delta
				if gun.is_reloading and not was_reloading: reload_count += 1
				was_reloading = gun.is_reloading
				var living = targets.filter(func(t): return is_instance_valid(t) and not t.is_die)
				if living.is_empty() and clear_seconds < 0:
					clear_seconds = (now-start)/1000.0
					break
				var point = living[0].global_position-Vector2(0,8) if not living.is_empty() else origin+Vector2(50,0)
				fire_at(point,delta)
				if id == 6: gun._physics_process(delta)
				for seconds in [1,3,5]:
					if now-start>=seconds*1000 and not burst.has(str(seconds)): burst[str(seconds)] = damage_total(targets)
				await wait(0.01)
			var elapsed = (Time.get_ticks_msec()-start)/1000.0
			var total = damage_total(targets)
			gun.cancel_actions()
			var row = {"id":id,"scenario":scenario,"raw":raw,"seconds":elapsed,"damage":total,"dps":total/elapsed,"burst":burst,"reload_seconds":reload_seconds,"reload_count":reload_count,"volleys":shots_fired,"clear_seconds":clear_seconds,"tier":WeaponCatalog.tier(id),"price":WeaponCatalog.PRICES[str(id)],"effective":gun.effective.duplicate(true),"boss_dummy":"high-health stationary BaseMonster with boss flag; no TacticalEnemy armor or behavior" if scenario=="boss" else ""}
			rows.append(row)
			row["name"] = tr(gun.weapon_name)
			print("M9_POWER ",JSON.stringify(row))
			DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/m9")
			var file = FileAccess.open("res://docs/iteration/evidence/m9/power-"+("raw" if raw else "final")+".json",FileAccess.WRITE)
			file.store_string(JSON.stringify(rows,"\t")); file.close()
			await clean()
	await Demo.quit_game()

func damage_total(targets):
	var total = 0.0
	for t in targets:
		if is_instance_valid(t): total += float(t.get_meta("initial_hp"))-maxf(0,t.HP)
		else: total += 30.0
	return total

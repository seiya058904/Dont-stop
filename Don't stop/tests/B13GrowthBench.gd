extends "res://tests/M9Power.gd"
## B13 growth benchmark: the same real-runtime fixture M9Power/B12WeaponBench use
## (single / crowd / boss, actual firing + reloads + health deltas), redirected to
## docs/iteration/evidence/b13/ and measuring GROWTH BUILDS instead of weapons.
##
## Builds (all on one representative mid weapon, id 0, level 1):
##   baseline              - no upgrades, no talents
##   upgrades_common       - the 9 普通 upgrades
##   upgrades_rare         - 普通 + 稀有 (18)
##   upgrades_full         - all 24
##   talents_common        - the 9 普通 talents at max rank
##   talents_rare          - 普通 + 稀有 talents at max rank
##   talents_full          - all 24 talents at max rank
##   both_full             - everything (the real late-game account)
## The score reads NOTHING from the catalogs: it is pure measured combat output, so it
## cannot argue in circles. The frozen JSON is asserted afterwards by B13Strength.

var build := "baseline"

func fire_at(point: Vector2, delta: float):
	Utils.aim_override = get_viewport().get_canvas_transform()*point
	super.fire_at(point,delta)

func apply_build(name: String):
	Demo.owned_global_upgrades.clear()
	Demo.talents.clear()
	Demo.talent_payments.clear()
	Demo.refresh()
	match name:
		"baseline": pass
		"upgrades_common":
			for id in AttachmentCatalog.QUALITY:
				if AttachmentCatalog.quality(int(id)) == 1: Demo.owned_global_upgrades.append(str(id))
		"upgrades_rare":
			for id in AttachmentCatalog.QUALITY:
				if AttachmentCatalog.quality(int(id)) <= 2: Demo.owned_global_upgrades.append(str(id))
		"upgrades_full":
			for id in AttachmentCatalog.QUALITY: Demo.owned_global_upgrades.append(str(id))
		"talents_common","talents_rare","talents_full":
			var ceiling := 1 if name == "talents_common" else (2 if name == "talents_rare" else 3)
			for id in DemoConfig.TALENTS:
				if DemoConfig.talent_quality(id) <= ceiling:
					Demo.talents[id] = DemoConfig.TALENTS[id].max
		"both_full":
			for id in AttachmentCatalog.QUALITY: Demo.owned_global_upgrades.append(str(id))
			for id in DemoConfig.TALENTS: Demo.talents[id] = DemoConfig.TALENTS[id].max
	Demo.owned_global_upgrades.sort()
	Demo.refresh()

func _ready():
	await boot()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--build="): build = arg.substr(8)
	var only_scenarios: Array = []
	for arg in args:
		if arg.begins_with("--scenario="): only_scenarios.append(arg.substr(11))
	apply_build(build)
	var gun_id := 0
	configure(gun_id,false)
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	var rows: Array = []
	for scenario in ["single","crowd","boss"]:
		if not only_scenarios.is_empty() and not only_scenarios.has(scenario): continue
		seed(909)
		PlayerData.player_level = 1
		PlayerData.player_exp = 0
		Demo.refresh()
		var gun = Utils.player.gun
		gun.updateGun()
		gun.bullets_count = gun.bullets_max_count
		PlayerData.reserve_magazines = 1000
		LevelServer.state = "COMBAT"
		var targets: Array = []
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
		var start := Time.get_ticks_msec()
		var previous_ms := start
		var reload_seconds := 0.0
		var was_reloading := false
		var clear_seconds := -1.0
		shots_fired = 0
		while Time.get_ticks_msec()-start < (180000 if scenario == "crowd" else 15000):
			var now := Time.get_ticks_msec()
			var delta := (now-previous_ms)/1000.0
			previous_ms = now
			if gun.is_reloading: reload_seconds += delta
			was_reloading = gun.is_reloading
			var living: Array = targets.filter(func(t): return is_instance_valid(t) and not t.is_die)
			if living.is_empty() and clear_seconds < 0:
				clear_seconds = (now-start)/1000.0
				break
			var point: Vector2 = living[0].global_position-Vector2(0,8) if not living.is_empty() else origin+Vector2(50,0)
			fire_at(point,delta)
			if gun_id == 6: gun._physics_process(delta)
			await wait(0.01)
		var elapsed := (Time.get_ticks_msec()-start)/1000.0
		var total: float = damage_total(targets)
		gun.cancel_actions()
		var row: Dictionary = {"build":build,"scenario":scenario,"seconds":elapsed,"damage":total,"dps":total/elapsed,"clear_seconds":clear_seconds,"volleys":shots_fired,"reload_seconds":reload_seconds,"magazine":int(gun.effective.magazine),"reload_s":float(gun.effective.reload),"damage_stat":float(gun.effective.damage),"crit":float(gun.effective.crit),"rate":float(gun.effective.rate),"owned_upgrades":Demo.owned_global_upgrades.size(),"talent_ranks":Demo.talents.values().filter(func(r): return r>0).size()}
		rows.append(row)
		print("B13_BENCH ",JSON.stringify(row))
		await clean()
	if only_scenarios.is_empty():
		DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/b13")
		var file = FileAccess.open("res://docs/iteration/evidence/b13/growth-%s.json" % build,FileAccess.WRITE)
		file.store_string(JSON.stringify(rows,"\t")); file.close()
	await Demo.quit_game()

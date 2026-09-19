extends "res://tests/M9Power.gd"
## B12 weapon benchmark: same real-runtime fixture as M9Power (single / crowd / boss,
## level-1 unupgraded build, actual firing + reloads + health deltas), redirected to
## docs/iteration/evidence/b12/<phase>/ and followed by a General Power Score summary.
##
## The General Power Score is computed ONLY from measured combat results. It never reads
## WeaponCatalog.tier(), WeaponCatalog.power(), PRICES or any rarity name, so it cannot
## argue in circles. Per weapon, four raw metrics:
##   B = damage dealt inside the first 3.0 s of the single scenario (burst)
##       (3 s, not 1 s: a 1 s window scores charged shots - rail 1.2 s charge - and
##       delayed detonations - gravity grenade ~1.35 s to impact - as literal zero,
##       collapsing their geometric mean to the 0.01 floor no matter how strong they
##       are. 3 s still separates burst from sustained: warmup/ramp/magazine limits
##       keep slow starters below fast starters inside the same window.)
##   S = single-scenario damage / elapsed seconds over the full window (sustained, reloads included)
##   C = 6 targets / crowd clear seconds (clearing speed; if the window expires uncleared,
##       the equivalent speed damage/(30*window) is used)
##   X = boss-scenario damage / elapsed seconds (high-health target output)
## Each is normalised by the MEDIAN across the 24 weapons; the score is the geometric mean
## (b*s*c*x)^(1/4), so no single extreme scenario can carry a weapon alone. It is a test /
## design metric only - never a hidden game attribute.

var phase := "before"

## The product reads its aim from the ROOT viewport mouse
## (Utils.get_aim_viewport_position = get_viewport().get_mouse_position on the autoload's
## viewport). The inherited fixture only pushes synthetic InputEventMouseMotion into
## play_view, a SubViewport - which never updates the root mouse. Every weapon whose
## _shoot re-derives its direction from Utils.get_aim_world_position() therefore fired
## toward a stale screen corner in headless: measured on the CURRENT main this zeroes
## weapons 0/2/3/5/7/9/114/115/116/119/121 even through the untouched M9Power harness.
## Real game and browser gates have a real mouse and are unaffected. Feeding the same
## aim point through the real input pipeline at the root, mapped by the root canvas
## transform, makes both aim readers agree; flushed synchronously so the very first
## shot of every scenario is already correct.
func fire_at(point: Vector2, delta: float):
	# Aim provider override: the root-viewport mouse cannot be driven by synthetic
	# input in headless (measured: it only follows the real OS cursor), so weapons
	# that re-derive their direction from Utils.get_aim_world_position() in _shoot
	# need the test hook. Viewport coords = root canvas transform of the world point,
	# exactly what get_aim_world_position() round-trips back to `point`.
	Utils.aim_override = get_viewport().get_canvas_transform()*point
	super.fire_at(point,delta)

func _ready():
	await boot()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--phase="): phase = arg.substr(8)
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	Demo.owned_global_upgrades.clear()
	Demo.talents.clear()
	Demo.refresh()
	var rows: Array = []
	var only_ids: Array = []
	var only_scenarios: Array = []
	for arg in args:
		if arg.begins_with("--id="): only_ids.append(int(arg.substr(5)))
		if arg.begins_with("--scenario="): only_scenarios.append(arg.substr(11))
	for key in Utils.weapon_list:
		var id := int(key)
		if not only_ids.is_empty() and not only_ids.has(id): continue
		configure(id,false)
		var gun = Utils.player.gun
		for scenario in ["single","crowd","boss"]:
			if not only_scenarios.is_empty() and not only_scenarios.has(scenario): continue
			seed(909)
			# Six crowd kills must not level later samples into a stronger build.
			PlayerData.player_level = 1
			PlayerData.player_exp = 0
			Demo.refresh()
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
			var burst: Dictionary = {}
			var previous_ms := start
			var reload_seconds := 0.0
			var reload_count := 0
			var was_reloading := false
			var clear_seconds := -1.0
			shots_fired = 0
			while Time.get_ticks_msec()-start < (180000 if scenario == "crowd" else 15000):
				var now := Time.get_ticks_msec()
				var delta := (now-previous_ms)/1000.0
				previous_ms = now
				if gun.is_reloading: reload_seconds += delta
				if gun.is_reloading and not was_reloading: reload_count += 1
				was_reloading = gun.is_reloading
				var living: Array = targets.filter(func(t): return is_instance_valid(t) and not t.is_die)
				if living.is_empty() and clear_seconds < 0:
					clear_seconds = (now-start)/1000.0
					break
				var point: Vector2 = living[0].global_position-Vector2(0,8) if not living.is_empty() else origin+Vector2(50,0)
				fire_at(point,delta)
				if id == 6: gun._physics_process(delta)
				for seconds in [1,3,5]:
					if now-start>=seconds*1000 and not burst.has(str(seconds)): burst[str(seconds)] = damage_total(targets)
				await wait(0.01)
			var elapsed := (Time.get_ticks_msec()-start)/1000.0
			var total: float = damage_total(targets)
			gun.cancel_actions()
			var row: Dictionary = {"id":id,"scenario":scenario,"phase":phase,"seconds":elapsed,"damage":total,"dps":total/elapsed,"burst":burst,"reload_seconds":reload_seconds,"reload_count":reload_count,"volleys":shots_fired,"clear_seconds":clear_seconds,"tier":WeaponCatalog.tier(id),"price":WeaponCatalog.PRICES[str(id)],"power_mul":WeaponCatalog.power(id),"base":gun.base_stats.duplicate(true),"effective":gun.effective.duplicate(true),"name":tr(gun.weapon_name),"boss_dummy":"high-health stationary BaseMonster with boss flag" if scenario=="boss" else ""}
			rows.append(row)
			print("B12_BENCH ",JSON.stringify(row))
			await clean()
	DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/b12/%s" % phase)
	var file = FileAccess.open("res://docs/iteration/evidence/b12/%s/power-%s.json" % [phase,phase],FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("B12_GPS ",JSON.stringify(gps_summary(rows)))
	await Demo.quit_game()

func median_of(values: Array) -> float:
	var nums: Array = []
	for v in values: nums.append(float(v))
	if nums.is_empty(): return 0.0
	nums.sort()
	var mid := int(nums.size()/2)
	return nums[mid] if nums.size()%2==1 else (nums[mid-1]+nums[mid])*0.5

func gps_summary(rows: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for row in rows:
		if not by_id.has(row.id): by_id[row.id] = {}
		by_id[row.id][row.scenario] = row
	var bursts: Array = []
	var sustains: Array = []
	var crowds: Array = []
	var bosses: Array = []
	var raw: Dictionary = {}
	for id in by_id:
		var scenarios: Dictionary = by_id[id]
		if not scenarios.has("single") or not scenarios.has("crowd") or not scenarios.has("boss"): continue
		var single: Dictionary = scenarios.single
		var crowd: Dictionary = scenarios.crowd
		var boss: Dictionary = scenarios.boss
		var burst := float(single.burst.get("3",0.0))
		var sustain := float(single.dps)
		var clear := float(crowd.clear_seconds)
		var crowd_speed := 6.0/clear if clear > 0.0 else float(crowd.damage)/(30.0*maxf(0.01,float(crowd.seconds)))
		var boss_dps := float(boss.dps)
		raw[int(id)] = {"burst":burst,"sustain":sustain,"crowd":crowd_speed,"boss":boss_dps,
			"name":single.get("name",""),"tier":int(single.tier),"price":int(single.price)}
		bursts.append(burst); sustains.append(sustain); crowds.append(crowd_speed); bosses.append(boss_dps)
	var mb := median_of(bursts); var ms := median_of(sustains)
	var mc := median_of(crowds); var mx := median_of(bosses)
	var scores: Dictionary = {}
	for id in raw:
		var r: Dictionary = raw[id]
		var b: float = r.burst/mb if mb > 0.0 else 0.0
		var s: float = r.sustain/ms if ms > 0.0 else 0.0
		var c: float = r.crowd/mc if mc > 0.0 else 0.0
		var x: float = r.boss/mx if mx > 0.0 else 0.0
		var score := pow(maxf(0.01,b)*maxf(0.01,s)*maxf(0.01,c)*maxf(0.01,x),0.25)
		scores[id] = {"gps":score,"name":r.name,"tier":r.tier,"price":r.price,
			"raw":{"burst":r.burst,"sustain":r.sustain,"crowd":r.crowd,"boss":r.boss}}
	# Per-tier medians of GPS, plus inversions against every higher tier.
	var per_tier: Dictionary = {}
	for id in scores:
		var t := int(scores[id].tier)
		if not per_tier.has(t): per_tier[t] = []
		per_tier[t].append(float(scores[id].gps))
	var tier_medians: Dictionary = {}
	for t in per_tier: tier_medians[t] = median_of(per_tier[t])
	var inversions: Array = []
	for a in scores:
		for b in scores:
			if a == b: continue
			var ta := int(scores[a].tier); var tb := int(scores[b].tier)
			if ta < tb-1 and float(scores[a].gps) > float(scores[b].gps):
				inversions.append({"low":a,"low_tier":ta,"gps_low":scores[a].gps,"high":b,"high_tier":tb,"gps_high":scores[b].gps})
	return {"medians":{"burst":mb,"sustain":ms,"crowd":mc,"boss":mx},
		"tier_medians":tier_medians,"inversions_2plus":inversions,"scores":scores,
		"formula":"GPS = (b*s*c*x)^(1/4), each = metric/median-of-24; metrics are burst(damage in first 3 s of single), sustained DPS(single), crowd clear speed(6/clear_s), boss DPS. No tier/price/POWER input."}

extends "res://tests/B12WeaponBench.gd"

var bench_rows: Array = []
var run_kills := 0
var run_overkill := 0.0
var first_kill := -1.0
var bench_time := 0.0
var locked_level := 1
var spawned_stats: Array = []

func spawn_chaser(index: int) -> bool:
	var role = "E01" if index%2 == 0 else "E02"
	var point = LevelServer.town.spawn_near(Utils.player.global_position,140,210,M5Content.radius_for(role))
	if point == Vector2.INF: return false
	var actor = M5Content.spawn(role,LevelServer.town.monster_root,point)
	if actor == null: return false
	# Freeze this protocol independently of subsequent encounter-table tuning.
	actor.HP = 2.0 if role=="E01" else 1.2
	actor.SPEED = 103.5 if role=="E01" else 105.0
	if spawned_stats.size()<2: spawned_stats.append({"role":role,"hp":actor.HP,"speed":actor.SPEED})
	actor.setDeathCallBack(func(dead):
		run_kills += 1
		run_overkill += maxf(0,-dead.HP)
		if first_kill<0: first_kill=bench_time
		PlayerData.player_exp = 0)
	return true

func _ready():
	await boot()
	var chosen: Array = []
	var builds: Array = ["bare","late"]
	var run_seed := 20260920
	var seconds := 15.0
	var tag := "reference"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): chosen.append(int(arg.substr(5)))
		if arg.begins_with("--build="): builds=[arg.substr(8)]
		if arg.begins_with("--seed="): run_seed=int(arg.substr(7))
		if arg.begins_with("--seconds="): seconds=float(arg.substr(10))
		if arg.begins_with("--tag="): tag=arg.substr(6)
	if chosen.is_empty(): chosen=[6,112,113,115,119,124,0,1,2,3,4,5,7,8,9,111,114,116,117,118,120,121,122,123]
	for id in chosen:
		for build_name in builds:
			stop(); await clean(); dismiss()
			seed(run_seed)
			LevelServer.timer.stop(); LevelServer.state="CAMP"
			locked_level=20 if build_name=="late" else 1
			PlayerData.player_level=locked_level; PlayerData.player_exp=0
			Demo.talents={"T01":3,"T02":3,"T03":3,"T04":3,"T08":3,"T10":1} if build_name=="late" else {}
			Demo.owned_global_upgrades=["0","1","111","115","118","120"] if build_name=="late" else []
			Demo.kill_stacks=0; Demo.stack_time=0
			Demo.refresh(); configure(id)
			var gun=Utils.player.gun
			gun.updateGun(); gun.bullets_count=gun.bullets_max_count; PlayerData.reserve_magazines=100
			LevelServer.level=39; LevelServer.epoch+=1
			LevelServer.town.prepare_region("R8")
			await wait(0.1)
			LevelServer.state="COMBAT"
			PlayerData.player_hp_max=100000; PlayerData.player_hp=100000; Utils.player.is_dead=false
			run_kills=0; run_overkill=0; first_kill=-1; bench_time=0; spawned_stats=[]
			var spawned=0
			for i in 12:
				if spawn_chaser(spawned): spawned+=1
			var start=Time.get_ticks_msec()
			var previous=start
			var next_spawn=1.0
			var sum_alive=0.0; var peak_alive=0; var near_seconds=0.0; var nearest=10000.0
			var reload_time=0.0; var reloads=0; var was_reload=false; var charge_seconds=0.0
			var lost_hp=0.0; var kills3=-1; var ammo_used=0; var last_ammo=gun.bullets_count
			var attacks=Combat.attacks; var hits=Combat.damage_events
			movement=0; last_position=Utils.player.global_position; bot_clock=0; moving=true; target_boss=false; driving=true
			while Time.get_ticks_msec()-start < seconds*1000:
				var now=Time.get_ticks_msec(); var delta=(now-previous)/1000.0; previous=now
				bench_time=(now-start)/1000.0
				var alive=get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die and not m.training)
				peak_alive=maxi(peak_alive,alive.size()); sum_alive+=alive.size()*delta
				var distance=10000.0
				for actor in alive: distance=minf(distance,actor.global_position.distance_to(Utils.player.global_position))
				nearest=minf(nearest,distance)
				if distance<45: near_seconds+=delta
				if bench_time>=next_spawn:
					next_spawn+=1
					for i in mini(6,64-alive.size()):
						if spawn_chaser(spawned): spawned+=1
				if gun.is_reloading: reload_time+=delta
				if gun.is_reloading and not was_reload: reloads+=1
				was_reload=gun.is_reloading
				if gun.get("charging")==true: charge_seconds+=delta
				ammo_used+=maxi(0,last_ammo-gun.bullets_count); last_ammo=gun.bullets_count
				lost_hp+=maxf(0,100000-PlayerData.player_hp); PlayerData.player_hp=100000
				if bench_time>=3 and kills3<0: kills3=run_kills
				if id==6: gun._physics_process(delta)
				await get_tree().process_frame
			stop()
			var row={"id":id,"build":build_name,"seed":run_seed,"seconds":bench_time,"map":"R8","fixture":"moving E01/E02, invulnerable observer, no claim of survival","spawned":spawned,"kills":run_kills,"kills_per_s":run_kills/bench_time,"first_kill_s":first_kill,"kills_3s":kills3,"alive_mean":sum_alive/bench_time,"alive_peak":peak_alive,"alive_end":spawned-run_kills,"nearest_enemy":nearest,"pressure_under45_s":near_seconds,"movement":movement,"hp_damage":lost_hp,"attacks":Combat.attacks-attacks,"hit_events":Combat.damage_events-hits,"ammo_used":ammo_used,"reloads":reloads,"reload_s":reload_time,"charge_s":charge_seconds,"overkill":run_overkill,"role_stats":spawned_stats,"effective":gun.effective.duplicate(true),"level":locked_level,"talents":Demo.talents.duplicate(),"upgrades":Demo.owned_global_upgrades.duplicate(),"tag":tag}
			bench_rows.append(row)
			print("B14_HORDE_ROW ",JSON.stringify(row))
			var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-horde-"+tag+".json",FileAccess.WRITE)
			file.store_string(JSON.stringify(bench_rows,"\t"));file.close()
	LevelServer.state="CAMP"
	print("B14_HORDE_DONE rows=",bench_rows.size())
	get_tree().quit.call_deferred()

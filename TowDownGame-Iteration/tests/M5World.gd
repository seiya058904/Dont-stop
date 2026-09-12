extends "res://tests/M3Weapons.gd"
func dismiss():
	for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
func _ready():
	Demo.test_mode = true; seed(505)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.5)
	Demo.try_purchase("weapon","117"); PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	var town = LevelServer.town
	check(M5Content.ENEMIES.size()==12 and M5Content.BOSSES.size()==3 and M5Content.REGIONS.size()==6 and DemoConfig.ENCOUNTERS.size()==30,"registered 12/3/6/30")
	for stage in DemoConfig.ENCOUNTERS:
		dismiss(); await wait(0.03)
		var progress = Demo.next_stage
		check(town.depart(stage,true),"enter stage "+str(stage))
		await wait(0.15)
		var config = DemoConfig.ENCOUNTERS[stage]
		if (stage-1)%5 == 0:
			var valid_spawns = 0
			var physical_clear = 0
			for fixed_seed in 100:
				seed(fixed_seed+1000)
				var point = town.spawn_point()
				if point == Vector2.INF or point.distance_to(Utils.player.global_position)<145: continue
				var path = town.arena.grid.get_id_path(town.arena.cell(point),town.arena.cell(Utils.player.global_position)) if is_instance_valid(town.arena) else town.navigation.get_id_path(town.nav_cell(point),town.nav_cell(Utils.player.global_position))
				if path.size()>1: valid_spawns += 1
				var circle = CircleShape2D.new(); circle.radius = 12 if is_instance_valid(town.arena) else 6
				var query = PhysicsShapeQueryParameters2D.new(); query.shape = circle; query.transform = Transform2D(0,point); query.collision_mask=2147483648
				if town.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): physical_clear += 1
			check(valid_spawns==100,"100 fixed seeds reachable "+config.region)
			check(physical_clear==100,"100 actual physics hull-clear spawns "+config.region)
			var mover = M5Content.spawn("E03",town.monster_root,town.spawn_point())
			var old = mover.global_position; await wait(1.3)
			check(mover.global_position.distance_to(old)>1,"region real actor exists and starts "+config.region)
		if config.has("boss"):
			var boss = instance_from_id(LevelServer.boss_instance)
			check(is_instance_valid(boss) and boss.is_boss,"boss battle exists "+config.boss)
			LevelServer.level_time = 0; LevelServer._timeout()
			check(LevelServer.state=="COMBAT" and not LevelServer.victory(),"boss cannot timer win "+config.boss)
			await wait(11.0)
			check(boss.actions.get("attack",0)>=2,"boss multiple natural actions "+config.boss)
			var before = boss.HP
			origin = boss.global_position-Vector2(25,8); aim(Utils.player.gun); Utils.player.gun._shoot(); await wait(0.1)
			check(boss.HP<before,"boss actual weapon hit "+config.boss)
			Combat.hit(boss,{"damage":boss.max_hp*0.8,"epoch":LevelServer.epoch}); await wait(0.1)
			if not boss.is_die and boss.HP>boss.max_hp*0.5: Combat.hit(boss,{"damage":boss.max_hp*0.4,"epoch":LevelServer.epoch}); await wait(0.1)
			check(boss.phase_two,"boss half health phase "+config.boss)
			Combat.hit(boss,{"damage":10000.0,"epoch":LevelServer.epoch}); await wait(0.1)
		else:
			await wait(1.8)
			check(get_tree().get_nodes_in_group("monsters").size()>0,"encounter actual spawns "+str(stage))
			LevelServer.level_time = 0.01; LevelServer._timeout()
		check(LevelServer.state=="CAMP" and Demo.next_stage==progress,"trial resolves without skipping progress "+str(stage))
		dismiss(); await wait(0.7)
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"stage cleanup "+str(stage))
	Demo.next_stage = 29; check(town.depart(29,false),"normal stage29 departure"); LevelServer.level_time = 0.01; LevelServer._timeout(); dismiss(); await wait(0.7)
	check(Demo.next_stage==30,"normal progression reaches30")
	check(town.depart(30,false),"normal final battle")
	await wait(0.8); var boss = instance_from_id(LevelServer.boss_instance); Combat.hit(boss,{"damage":10000.0,"epoch":LevelServer.epoch}); await wait(0.1)
	check(Demo.campaign_complete and Demo.next_stage==30 and LevelServer.state=="CAMP","final campaign resolves without stage31")
	dismiss(); await wait(0.7)
	var snap = Demo.snapshot(); check(CampSnapshot.validate(snap) and snap.schema_version==5 and snap.campaign_complete,"schema4 completed campaign snapshot")
	for version in [1,2,3]:
		var old = snap.duplicate(true); old = M7Fixtures.legacy(old,version); old.erase("campaign_complete")
		check(CampSnapshot.validate(old) and not CampSnapshot.normalize(old).campaign_complete,"old schema defaults without invented completion "+str(version))
	print("M5 WORLD SUMMARY checks=",checks," failures=",failures)
	await wait(1.0); get_tree().quit(1 if failures else 0)

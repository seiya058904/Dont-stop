extends "res://tests/M3Weapons.gd"
func dismiss():
	for p in Demo.pause_stack.duplicate(): Demo.pop_pause(p); p.queue_free()
func _ready():
	Demo.test_mode=true; seed(550)
	var main=load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); await wait(0.5)
	Demo.try_purchase("weapon","117"); var town=LevelServer.town
	town.depart(6,true); LevelServer.timerStop(); await wait(0.2)
	PlayerData.player_hp_max=500; PlayerData.player_hp=500; Utils.player.set_physics_process(false); Utils.player.set_process(false)
	var point=Utils.player.global_position+Vector2(80,0)
	var shield=M5Content.spawn("E09",town.monster_root,point); shield.set_physics_process(false); shield.facing=Vector2.LEFT
	var hp=shield.HP
	Combat.hit(shield,{"damage":2.0,"impact_origin":point-Vector2(20,0),"epoch":LevelServer.epoch})
	check(is_equal_approx(hp-shield.HP,0.9),"shield actual front mitigation")
	hp=shield.HP; Combat.hit(shield,{"damage":2.0,"impact_origin":point+Vector2(20,0),"epoch":LevelServer.epoch})
	check(is_equal_approx(hp-shield.HP,2.0),"shield rear weakness")
	Combat.hit(shield,{"damage":6.0,"impact_origin":point-Vector2(20,0),"epoch":LevelServer.epoch}); check(shield.armor==0,"shield breaks finite armor")
	await clean()
	var hp_before=PlayerData.player_hp
	var warning=load("res://game/monster/HostileZone.gd").new(); warning.position=Utils.player.global_position; warning.warning=0.1; warning.damage=0; add_child(warning); await wait(0.35)
	check(PlayerData.player_hp==hp_before,"zero damage warning cannot damage player")
	var owner=M5Content.spawn("E10",town.monster_root,point); owner.set_physics_process(false)
	owner.locked_direction=Vector2.LEFT
	var zone=owner.zone("circle",Utils.player.global_position,35,0.5)
	Demo.push_pause(self); await wait(0.6); check(zone.elapsed==0,"pause freezes pending hazard")
	Demo.pop_pause(self); Combat.hit(owner,{"damage":100.0,"epoch":LevelServer.epoch}); await wait(0.7)
	check(PlayerData.player_hp==hp_before and not is_instance_valid(zone),"owner death cancels warning damage")
	var self_bomber=M5Content.spawn("E06",town.monster_root,Utils.player.global_position+Vector2(25,0)); await wait(0.8)
	Combat.hit(self_bomber,{"damage":100.0,"epoch":LevelServer.epoch}); await wait(1.0)
	check(PlayerData.player_hp==hp_before,"early self-bomber kill cancels blast")
	await clean()
	var armor=M5Content.spawn("E03",town.monster_root,point); armor.set_physics_process(false)
	var support=M5Content.spawn("E08",town.monster_root,point+Vector2(15,0)); support.set_physics_process(false)
	var amount=0.0
	for i in 12:
		armor.HP=1; support.perform_attack(); amount+=armor.HP-1
	check(is_equal_approx(amount,3.0),"support lifetime heal budget cannot cycle infinitely")
	await clean()
	var mother=M5Content.spawn("E07",town.monster_root,point); mother.set_physics_process(false)
	mother.summon(20); mother.summon(20)
	check(mother.summon_total==3,"producer hard total and live cap")
	Combat.hit(mother,{"damage":100.0,"epoch":LevelServer.epoch}); await wait(0.1)
	check(mother.summon_total==3,"death split shares production budget")
	await clean()
	var victims=[]
	for i in 12:
		var v=M5Content.spawn("E12",town.monster_root,point+Vector2(i%4*12,i/4*12)); v.set_physics_process(false); victims.append(v)
	Combat.hit(victims[0],{"damage":10.0,"depth":0,"epoch":LevelServer.epoch}); await wait(1.1)
	check(Combat.max_depth_seen<=2 and get_tree().get_nodes_in_group("hostile_zone").is_empty(),"death blasts bounded depth and end")
	await clean()
	var arena=town.arena; var rect=arena.obstacles[0]; var middle=arena.to_global(rect.get_center())
	Utils.player.global_position=middle+Vector2(rect.size.x/2+30,0); hp_before=PlayerData.player_hp
	var shot=CharacterBody2D.new(); shot.set_script(load("res://game/monster/EnemyShot.gd")); shot.position=middle-Vector2(rect.size.x/2+30,0); shot.velocity=Vector2(1500,0); add_child(shot); await wait(0.2)
	check(PlayerData.player_hp==hp_before and not is_instance_valid(shot),"fast hostile projectile stopped by physical cargo wall")
	var line=load("res://game/monster/HostileZone.gd").new(); line.mode="line"; line.length=300; line.direction=Vector2.RIGHT; line.warning=0.1; line.position=middle-Vector2(rect.size.x/2+30,0); add_child(line); await wait(0.4)
	check(PlayerData.player_hp==hp_before,"hostile beam actual wall occlusion")
	LevelServer.return_to_camp(); dismiss(); await wait(0.8)
	# New weapons versus new enemy roles: physical hits, then target release while attacks live.
	var guns=[117,118,119,120,111,113,115,116,121,122,124,112,114]
	var roles=["E03","E07","E09","E11","E10","E08","E06","E12"]
	for i in guns.size():
		var id=guns[i]; Demo.try_purchase("weapon",str(id)); LevelServer.state="COMBAT"
		var enemy=M5Content.spawn(roles[i%roles.size()],town.monster_root,Vector2(50,-1992)); enemy.set_physics_process(false); enemy.HP=200
		Utils.player.global_position=Vector2(-100,-2000); origin=Vector2(0,-2000); var gun=PlayerData.player_weapon_list[id]; aim(gun)
		var before=enemy.HP; gun._shoot(); await wait(1.7 if id==121 else 0.7)
		check(enemy.HP<before,"special gun actual new enemy hit "+str(id)+"/"+roles[i%roles.size()])
		enemy.queue_free(); await wait(2.1)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"released target has finite projectile lifetime "+str(id))
		LevelServer.return_to_camp(); dismiss(); await wait(0.2)

	for resume in [true,false]:
		PlayerData.resurrectPlayer(50,100); LevelServer.state="CAMP"; dismiss()
		town.depart(10,true); await wait(0.8)
		var boss=instance_from_id(LevelServer.boss_instance)
		Combat.hit(boss,{"damage":10000.0,"epoch":LevelServer.epoch})
		Utils.player.onHit(PlayerData.player_hp+1)
		await wait(0.1)
		check(LevelServer.state=="DEAD","simultaneous boss/player death keeps death choice")
		var wallet=PlayerData.gold
		dismiss(); PlayerData.resurrectPlayer(50,100)
		if resume:
			LevelServer.state="COMBAT"; LevelServer._timeout(); await wait(0.1)
			check(LevelServer.state=="CAMP" and PlayerData.gold==wallet+20,"revive resolves already defeated boss once")
		else:
			LevelServer.return_to_camp(); await wait(0.1)
			check(LevelServer.state=="CAMP" and PlayerData.gold==wallet,"abandon after double death grants no victory")
		dismiss(); await wait(0.7)
	print("M5 MECHANICS SUMMARY checks=",checks," failures=",failures)
	await wait(1.0); get_tree().quit(1 if failures else 0)

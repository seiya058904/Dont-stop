extends "res://tests/M8Runtime.gd"
var records = []
func owned(actor):
	return get_tree().get_nodes_in_group("hostile_zone").filter(func(z): return z.owner_ref and z.owner_ref.get_ref()==actor and not z.is_queued_for_deletion())
func capture(name):
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var picture = play_view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	picture.save_png("res://docs/iteration/evidence/m8/r1-"+name+".png")
func _ready():
	await boot(); configure(124)
	LevelServer.town.depart(20,true); LevelServer.timerStop(); await clean()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
	var center = LevelServer.town.arena.global_position
	for camera in get_tree().get_nodes_in_group("camera"): camera.enabled = false
	var camera = Camera2D.new(); play_view.add_child(camera); camera.global_position = center; camera.make_current()
	var attacks = {"B01":["charge","cleave","slam"],"B02":["brood","lockdown","pulse"],"B03":["dash","sweep","burst"]}
	for id in attacks:
		for second in [false,true]:
			for index in 3:
				LevelServer.state = "COMBAT"; Utils.player.global_position = center+Vector2(55,0)
				var actor = M5Content.spawn(id,LevelServer.town.monster_root,center-Vector2(55,0))
				actor.set_physics_process(false); actor.phase_two = second; actor.attack_index = index
				if second: actor.phase_label.text = M5Content.definition(id).name+" · PHASE II"
				actor.choose_attack()
				var action = attacks[id][index]; var label = id+"-"+action+"-"+("II" if second else "I")
				var zones = owned(actor); var refs = zones.map(func(z): return weakref(z))
				check(actor.phase=="warn" and actor.attack_kind==action and not zones.is_empty(),label+" owns actual warning nodes")
				await wait(actor.phase_time*0.5)
				var modes = []
				for zone in zones:
					modes.append(zone.mode)
					check(is_instance_valid(zone) and zone.elapsed<zone.warning and zone.hit_count==0 and zone.is_visible_in_tree(),label+" visible harmless windup")
					if DisplayServer.get_name()!="headless": check(not zone.geometry_cache.is_empty(),label+" renderer consumed geometry")
				if action=="brood":
					check(zones.size()==1 and zones[0].mode=="summon" and zones[0].damage==0 and actor.summon_total==0,label+" identifiable summon signal before children")
				await capture(label+"-warn")
				# Let the authored warning elapse; execute the production attack once.
				await wait(actor.phase_time*0.5)
				actor.perform_attack()
				if action=="brood": check(actor.summon_total>0,label+" real summon after windup")
				await wait(1.8)
				check(refs.all(func(ref): return not is_instance_valid(ref.get_ref())),label+" warning cleaned after attack")
				records.append({"boss":id,"action":action,"phase_two":second,"modes":modes,"cleanup":owned(actor).size()})
				await clean()
	# Interrupt brood at each real lifecycle boundary, in both phases where applicable.
	for ending in ["death","transition","camp","epoch"]:
		LevelServer.state = "COMBAT"; Utils.player.global_position = center+Vector2(55,0)
		var actor = M5Content.spawn("B02",LevelServer.town.monster_root,center-Vector2(55,0))
		actor.set_physics_process(false); actor.choose_attack()
		var refs = owned(actor).map(func(z): return weakref(z))
		check(refs.size()==1,"brood interruption fixture "+ending)
		match ending:
			"death": actor.onDie(false)
			"transition": actor.HP=actor.max_hp*0.49; actor._physics_process(1.0/60.0)
			"camp": LevelServer.return_to_camp(); dismiss()
			"epoch": LevelServer.epoch += 1
		await wait(0.1)
		check(refs.all(func(ref): return not is_instance_valid(ref.get_ref())),"brood cleared on "+ending)
		await clean()
	# Cached warning clipping must still observe a new wall and moving origins;
	# activation and rotating sweeps must use current geometry every physics tick.
	LevelServer.state = "COMBAT"; Utils.player.global_position = origin+Vector2(20,0)
	var zone = load("res://game/monster/HostileZone.gd").new(); zone.mode="line"; zone.position=origin; zone.warning=0.5; zone.duration=0.4; zone.sweep=0.8; add_child(zone)
	await wait(0.08); var barrier=wall(origin+Vector2(70,0),Vector2(8,100)); await wait(0.13)
	check(zone.length<75 and zone.hit_count==0,"cached warning observes added wall without early damage")
	zone.position += Vector2(10,0); await wait(0.04)
	check(zone.length<60,"moving origin invalidates ray cache")
	barrier.queue_free(); await wait(0.3)
	check(zone.activated and zone.length>100 and zone.direction!=Vector2.RIGHT,"activation refreshes clipping and sweep")
	await wait(0.5); check(not is_instance_valid(zone),"sweep cleanup remains exact")
	# Exercise the real visual budget with all 60 footprints retained.
	for i in 60:
		var busy = load("res://game/monster/HostileZone.gd").new()
		busy.mode=["circle","line","cone"][i%3]; busy.damage=0; busy.warning=0.8; busy.duration=0.3
		busy.position=center+Vector2((i%10-5)*25,(i/10-3)*25); busy.radius=35; busy.length=140; add_child(busy)
	await wait(0.3)
	var busy_zones=get_tree().get_nodes_in_group("hostile_zone")
	check(busy_zones.size()==60 and busy_zones.all(func(z): return z.elapsed<z.warning and z.hit_count==0),"visual budget retains 60 harmless warning footprints")
	if DisplayServer.get_name()!="headless":
		check(busy_zones.all(func(z): return not z.geometry_cache.is_empty()),"all 60 warning geometries rendered under budget")
		check(not load("res://game/monster/HostileZone.gd").full_detail,"stress activates decorative-only budget")
	await capture("stress-60-warn")
	await wait(0.9); check(get_tree().get_nodes_in_group("hostile_zone").is_empty(),"all 60 budgeted warnings finish on original deadlines")
	LevelServer.return_to_camp(); dismiss(); await clean()
	var file=FileAccess.open("res://docs/iteration/evidence/m8/r1-telegraph-contracts.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t")); file.close()
	print("M8 R1 TELEGRAPHS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

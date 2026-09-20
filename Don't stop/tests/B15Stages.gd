extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	await clean()
	var parent = Node2D.new(); add_child(parent)
	LevelServer.level = 31
	for id in ["E01","E02","E04"]:
		var actor = M5Content.spawn(id,parent,origin)
		actor.set_physics_process(false)
		await get_tree().physics_frame
		print("SPAWN_FINAL ",id," hp=",actor.HP," speed=",actor.SPEED)
		var expected = DemoConfig.ENCOUNTERS[31].get("pressure",{}).get("final_ordinary_hp",0.0) if id in ["E01","E02"] else M5Content.definition(id).hp*HellMode.hp_scale(31)
		check(actor.HP >= expected-0.001,"final initialized Hell HP "+id)
		actor.queue_free(); await wait(0.02)
	var rows = []
	for stage in range(1,41):
		LevelServer.level = stage
		var row = DemoConfig.ENCOUNTERS[stage].duplicate(true)
		row.stage = stage
		row.actual_instances = []
		for id in ["E01","E02"]:
			var actor = M5Content.spawn(id,parent,origin)
			actor.set_physics_process(false)
			await get_tree().physics_frame
			row.actual_instances.append({"id":id,"hp":actor.HP,"speed":actor.SPEED})
			var pressure: Dictionary = DemoConfig.ENCOUNTERS[stage].get("pressure",{})
			var base_expected = pressure.get("final_ordinary_hp",0.0) if id in ["E01","E02"] and pressure.has("final_ordinary_hp") else M5Content.definition(id).hp*HellMode.hp_scale(stage)
			var variant = int(actor.get_meta("enchantment",0))
			var expected = M5Content.giant_final_hp(stage) if actor.get_meta("giant",false) else base_expected*(2.0 if variant==1 else (4.0 if variant==2 else 1.0))
			check(is_equal_approx(actor.HP,expected),"HP applied once stage %d %s" % [stage,id])
			actor.queue_free(); await get_tree().process_frame
		for id in row.roles: check(stage>=M5Content.FIRST_APPEARANCE.get(id,1),"roster identity allowed %d %s" % [stage,id])
		row.hazards = ArenaHazards.plan(stage)
		row.horde = M5Content.HORDES.get(stage,{})
		rows.append(row)
	LevelServer.level = 3
	var early = M5Content.spawn("E14",parent,origin,true)
	check(early.get_meta("content_id")=="E01","summoned early high-tier enemy is replaced by plain chaser")
	M5Content.promote_elite(early)
	check(not early.is_elite,"early elite promotion forbidden")
	var file = FileAccess.open("res://evidence/visual-upgrade-20260919/b15-stage-table.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("B15 STAGES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

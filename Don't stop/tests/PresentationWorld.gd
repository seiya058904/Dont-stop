extends "res://tests/B8Runtime.gd"

var output: String
func save_view(name: String):
	await settle_render()
	play_view.get_texture().get_image().save_png(output+"/"+name+".png")

func clear_actors():
	for group in ["monsters","combat_transient"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): node.queue_free()
	await wait(0.15)

func _ready():
	await boot()
	dismiss()
	output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	configure(124,false)
	PlayerData.player_hp_max = 100000
	PlayerData.player_hp = 100000
	for stage in [1,6,11,16,21,26,31,36]:
		LevelServer.return_to_camp()
		await wait(0.2)
		dismiss()
		check(LevelServer.town.depart(stage,true),"region observation departure "+str(stage))
		await wait(0.3)
		await visual_ready(Vector2i(410,230))
		await freeze_room()
		recenter()
		await save_view("region-"+str(stage))
	LevelServer.return_to_camp()
	await wait(0.2)
	dismiss()
	LevelServer.town.depart(6,true)
	await wait(0.3)
	await visual_ready(Vector2i(410,230))
	await freeze_room()
	recenter()
	var records: Array = []
	for role in M5Content.ENEMIES:
		await clear_actors()
		var actor = M5Content.spawn(role,LevelServer.town.monster_root,Utils.player.global_position+Vector2(90,0))
		if role == "E08":
			var ally = M5Content.spawn("E03",LevelServer.town.monster_root,Utils.player.global_position+Vector2(95,20))
			ally.HP = 1
		var previous = 0.0
		for moment in [0.2,1.0,2.5,5.5]:
			await wait(moment-previous)
			previous = moment
			PlayerData.player_hp = PlayerData.player_hp_max
			await save_view("enemy-%s-%03d" % [role,roundi(moment*10)])
		records.append({"role":role,"alive":is_instance_valid(actor) and not actor.is_die,"zones":get_tree().get_nodes_in_group("hostile_zone").size(),"shots":get_tree().get_nodes_in_group("enemy_projectiles").size()})
		print("WORLD_CAPTURE ",role)
	var modifiers = load("res://game/monster/TacticalEnemy.gd").ELITE_MODIFIERS
	for role in modifiers:
		await clear_actors()
		var actor = M5Content.spawn(role,LevelServer.town.monster_root,Utils.player.global_position+Vector2(75,0))
		M5Content.promote_elite(actor,modifiers[role])
		await wait(0.25)
		await save_view("elite-"+role+"-"+modifiers[role])
		print("WORLD_ELITE ",modifiers[role])
	var record = FileAccess.open(output+"/observations.json",FileAccess.WRITE)
	record.store_string(JSON.stringify(records,"\t"))
	record.close()
	stop()
	print("WORLD_CAPTURE_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

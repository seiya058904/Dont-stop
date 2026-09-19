extends "res://tests/B5Bosses.gd"

# Reuses the existing real-fire boss contracts. Screenshots are observations,
# never a substitute for phase/ultimate/cleanup assertions in fight().
var output: String
var observed: Dictionary = {}
var capturing := false
var sample_clock := 0.0
var phase_three_entry: Dictionary = {}

func fire_at(point: Vector2, delta: float):
	var boss = instance_from_id(LevelServer.boss_instance)
	if is_instance_valid(boss) and boss.phase_three:
		var id = boss.get_instance_id()
		if not phase_three_entry.has(id): phase_three_entry[id] = boss.actions.duplicate()
		# Let the real Phase III attack cycle complete before the bot kills its subject.
		# This changes only the observer's trigger input, never HP, AI or the assertions.
		for attack in PHASES[boss.role]["3"]:
			if boss.actions.get(attack,0) <= phase_three_entry[id].get(attack,0): return
	super.fire_at(point,delta)

func record_view(key: String):
	capturing = true
	await settle_render()
	play_view.get_texture().get_image().save_png(output+"/"+key+".png")
	capturing = false

func _process(delta):
	super._process(delta)
	if output.is_empty() or not driving: return
	recenter()
	sample_clock += delta
	if sample_clock < 0.1 or capturing: return
	sample_clock = 0
	var boss = instance_from_id(LevelServer.boss_instance)
	if not is_instance_valid(boss): return
	var tier = "3" if boss.phase_three else ("2" if boss.phase_two else "1")
	var key = "%s-phase%s-%s-%s" % [boss.role,tier,boss.phase,boss.attack_kind]
	for ultimate in get_tree().get_nodes_in_group("boss_ultimate"):
		key = "%s-ultimate-%s" % [boss.role,"active" if ultimate.activated else "warning"]
	if not observed.has(key):
		observed[key] = true
		record_view(key)

func _ready():
	await boot()
	output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	await visual_ready(Vector2i(410,230))
	var rows: Array = []
	var requested = OS.get_environment("PRESENTATION_BOSS_STAGES").split(",",false)
	for stage in [10,20,30,40]:
		if not requested.is_empty() and not str(stage) in requested: continue
		var cleared := false
		for attempt in CLEAR_ATTEMPTS:
			var result = await fight(stage,STAGE_BOSS[stage],400,300000,true,false)
			rows.append(result)
			print("PRESENTATION_BOSS_ATTEMPT ",JSON.stringify(result))
			if result.get("clear",false) and not result.get("death",true):
				cleared = true
				break
		check(cleared,"rendered boss cleared by real fire "+str(stage))
	var file = FileAccess.open(output+"/bosses.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("PRESENTATION_BOSSES CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	var rows=[]
	for stage in range(30,41):
		var row=DemoConfig.ENCOUNTERS[stage].duplicate(true)
		row.stage=stage; row.fog=HellMode.has_fog(stage)
		row.light_radius=HellMode.visible_radius(stage); row.light_scale=HellMode.light_scale(stage)
		row.hell=HellMode.is_hell(stage); row.hp_axis=HellMode.hp_scale(stage) if row.hell else 1.0
		rows.append(row)
	var script=load("res://game/monster/TacticalEnemy.gd")
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b17-tables.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"difficulty":rows,"boss_cycles":script.BOSS_CYCLES,"elite_modifiers":script.ELITE_MODIFIERS},"\t")); file.close()
	check(rows.size()==11,"live stage30 through40 table exported")
	get_tree().quit(1 if failures else 0)

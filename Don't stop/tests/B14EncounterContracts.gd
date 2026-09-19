extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	check(DemoConfig.ENCOUNTERS[1].roles==["E01","E01","E02"] and DemoConfig.ENCOUNTERS[2].roles==["E02","E02","E01"],"starter rosters unchanged")
	for stage in range(21,40):
		var row=DemoConfig.ENCOUNTERS[stage]
		if row.has("boss"):continue
		var ordinary=row.roles.filter(func(id):return id in ["E01","E02"]).size()
		check(float(ordinary)/row.roles.size()>=0.8,"ordinary authored roster >=80 percent stage %d"%stage)
		check(row.pressure.horde_simple>=0.8 and row.pressure.special_cap<=3,"horde and live-special budgets stage %d"%stage)
		check(row.pressure.ring_min>=110,"safe spawn ring never shortened stage %d"%stage)
	LevelServer.timer.stop();LevelServer.level=39;LevelServer.epoch+=1
	LevelServer.town.prepare_region("R8");await wait(0.1);LevelServer.state="COMBAT"
	for i in 30:
		var role="E14" if i%2 else "E13"
		var point=LevelServer.town.spawn_near(Utils.player.global_position,140,210,M5Content.radius_for(role))
		var actor=M5Content.spawn(role,LevelServer.town.monster_root,point,i%3==0)
		if actor!=null:M5Content.promote_elite(actor)
	var mix=M5Content.living_mix(get_tree())
	check(mix.special<=3 and mix.ordinary>=mix.total*0.8,"all shared spawn sources and promotions obey live mix budget")
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.get_meta("content_id","") in ["E01","E02"]:
			check(actor.SPEED>105 and actor.SPEED<=112,"actual late ordinary initialized speed is bounded")
	check(DemoConfig.ENCOUNTERS[39].cap==84 and DemoConfig.ENCOUNTERS[29].cap==145,"existing total caps retained")
	await clean()
	LevelServer.level=1
	for id in ["E01","E02"]:
		var actor=M5Content.spawn(id,LevelServer.town.monster_root,LevelServer.town.spawn_near(Utils.player.global_position,140,210,M5Content.radius_for(id)))
		check(is_equal_approx(actor.SPEED,M5Content.definition(id).speed),"starter actual speed unchanged "+id)
	print("B14_ENCOUNTER_CONTRACTS checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

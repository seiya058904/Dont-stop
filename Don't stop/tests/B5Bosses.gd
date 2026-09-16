extends "res://tests/B8Runtime.gd"

## Boss audit for the 3-phase rework, covering stages 10 / 20 / 30 / 40.
##
## Rules this scene obeys, per the batch brief:
##   * the boss dies from the player's REAL weapon fire. Nothing here calls perform_attack(),
##     sets boss.HP, or injects damage to manufacture a pass;
##   * every phase must be reached by real DPS, and each phase's own attack list must be
##     observed executing in that phase;
##   * a phase transition is sampled as a real safe window: while `phase` is "transition"
##     the boss owns zero live attacks;
##   * the percentage ultimate is measured off Hero.incoming_hit, so the claim "the ultimate
##     is a percentage of MAX HP, not flat damage" is read from the damage pipeline.
##
## Two passes per boss:
##   OBSERVED  the player is given a durable pool so all three phases are reachable inside the
##             audit budget; the boss still dies to real fire only. This is the run that can
##             assert the phase contract.
##   AUTHORED  (stage 40 only) the authored HP pool, so the real-difficulty clear and TTK are
##             reported rather than asserted.
const PHASES = {
	"B01":{"1":["charge","cleave","slam"],"3":["charge","slam","shockwave"]},
	"B02":{"1":["brood","lockdown","pulse"],"3":["toxic_zone","root_shot","brood"]},
	"B03":{"1":["dash","sweep","burst"],"3":["cross_laser","sweep","burst"]},
	"B04":{"1":["dash","sweep","burst"],"2":["sweep","dash","cross","band"],"3":["cross_laser","sweep","band"]}
}
const STAGE_BOSS = {10:"B01",20:"B02",30:"B03",40:"B04"}

func fight(stage: int, boss_id: String, durable_hp: int, budget_ms: int, observe: bool) -> Dictionary:
	stop(); dismiss()
	if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
	configure(124,true)
	PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
	PlayerData.player_hp_max = durable_hp; PlayerData.player_hp = durable_hp
	check(LevelServer.town.depart(stage,true),"boss depart "+str(stage))
	var boss = instance_from_id(LevelServer.boss_instance)
	check(is_instance_valid(boss),"stage %d spawns %s" % [stage,boss_id])
	if not is_instance_valid(boss): return { }
	check(boss.role == boss_id,"stage %d fields %s" % [stage,boss_id])
	check(not boss.phase_two and not boss.phase_three,"stage %d boss starts in Phase I" % stage)
	check(absf(boss.max_hp-M5Content.BOSSES[boss_id].hp) < 1.0,"%s uses its authored HP" % boss_id)

	var seen = {"two":false,"three":false}
	var transition_violations = 0
	var warnings = {}
	var transition_samples = 0
	var phase_view = {"1":{},"2":{},"3":{}}
	var percentage_hits = []
	# The boss frees itself shortly after dying, so the action ledger is snapshotted every
	# sample rather than read off a possibly-freed node afterwards.
	var final_actions = boss.actions.duplicate()
	var observer = func(raw, applied, from_boss):
		if from_boss: percentage_hits.append({"raw":raw,"applied":applied})
	Utils.player.incoming_hit.connect(observer)

	shots_fired = 0; movement = 0; last_position = Utils.player.global_position
	target_boss = true; driving = true
	var start = Time.get_ticks_msec()
	var peak_zones = 0
	while LevelServer.state == "COMBAT" and Time.get_ticks_msec()-start < budget_ms:
		await wait(0.05)
		if not is_instance_valid(boss): break
		var tier = "3" if boss.phase_three else ("2" if boss.phase_two else "1")
		if boss.phase_three: seen.three = true
		if boss.phase_two: seen.two = true
		var owned = 0
		for zone in get_tree().get_nodes_in_group("hostile_zone"):
			if zone.owner_ref and zone.owner_ref.get_ref() == boss:
				owned += 1
				if zone.elapsed < zone.warning: warnings["%s:%s" % [tier,boss.attack_kind]] = zone.mode
		peak_zones = maxi(peak_zones,owned)
		final_actions = boss.actions.duplicate()
		for attack in final_actions:
			phase_view[tier][attack] = final_actions[attack]
		if boss.phase == "transition":
			transition_samples += 1
			# A phase change must be a real pause: no owned attack may be alive through it.
			if owned > 0: transition_violations += 1
	driving = false
	Utils.player.incoming_hit.disconnect(observer)
	var seconds = (Time.get_ticks_msec()-start)/1000.0
	var row = {
		"stage":stage,"boss":boss_id,"durable_hp":durable_hp,"observe":observe,
		"seconds":seconds,"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,
		"death":Utils.player.is_dead,"shots":shots_fired,"movement":movement,
		"phase_two":seen.two,"phase_three":seen.three,
		"transition_samples":transition_samples,"transition_violations":transition_violations,
		"peak_owned_zones":peak_zones,"actions":final_actions,
		"percentage_hits":percentage_hits.size(),
		"warnings":warnings.size()
	}
	if observe:
		check(seen.two,"%s reached Phase II by real damage" % boss_id)
		check(seen.three,"%s reached Phase III by real damage" % boss_id)
		check(transition_violations == 0,"%s phase transitions have no live owned attack (sampled %d)" % [boss_id,transition_samples])
		check(transition_samples >= 2,"%s transition window was actually sampled" % boss_id)
		for phase in PHASES[boss_id]:
			for attack in PHASES[boss_id][phase]:
				check(final_actions.get(attack,0) > 0,"%s ran %s" % [boss_id,attack])
				check(phase_view[phase].get(attack,0) > 0,"%s ran %s during Phase %s" % [boss_id,attack,phase])
				check(warnings.has("%s:%s" % [phase,attack]),"%s showed a real windup telegraph for %s in Phase %s" % [boss_id,attack,phase])
		check(final_actions.get("phase_two",0) == 1,"%s entered Phase II exactly once" % boss_id)
		check(final_actions.get("phase_three",0) == 1,"%s entered Phase III exactly once" % boss_id)
		check(final_actions.get("ultimate_activated",0) > 0,"%s fired its percentage ultimate" % boss_id)
		check(final_actions.get("ultimate_hit",0) > 0,"%s ultimate connected at least once" % boss_id)
		# Percentage, not flat: the raw payload is a share of MAX HP.
		var fraction = {"B01":0.30,"B02":0.28,"B03":0.33,"B04":0.30}[boss_id]
		var matched = 0
		for hit in percentage_hits:
			if absf(hit.raw-durable_hp*fraction) < maxf(0.5,durable_hp*0.02): matched += 1
		check(matched > 0,"%s ultimate paid a percentage of maximum HP (%d of %d boss hits)" % [boss_id,matched,percentage_hits.size()])
		check(row.clear and not row.death,"%s was really cleared by real fire" % boss_id)
	stop(); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
	check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),
		"boss cleanup "+str(stage))
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"boss stage leaves no hazard "+str(stage))
	check(not ArenaVisibility.fog_active(),"camp is bright after "+str(stage))
	return row

func _ready():
	await boot()
	var rows = []
	# OBSERVED pass: durable pool, real fire only. 60 HP so three phases of percentage
	# ultimates and contact pressure stay survivable for the audit.
	for stage in [10,20,30,40]:
		rows.append(await fight(stage,STAGE_BOSS[stage],60,190000,true))
		print("B5 BOSS ",JSON.stringify(rows[-1]))
	# AUTHORED pass: the real difficulty of the new final boss, reported not asserted.
	var hell_row = await fight(40,"B04",8,200000,false)
	rows.append(hell_row)
	print("B5 BOSS AUTHORED ",JSON.stringify(hell_row))
	var file = FileAccess.open("res://docs/iteration/evidence/b/bosses.json",FileAccess.WRITE)
	DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/b")
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("B5 BOSSES CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

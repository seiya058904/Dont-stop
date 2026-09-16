extends "res://tests/B8Probe.gd"

## B8 Boss fairness sampling.
##
## The question this scene answers is narrow and it is NOT "make the bot win": a three-phase
## boss at the AUTHORED 8 HP pool is meant to be brutal, and the brief is explicit that a
## high-variance result is acceptable when the death came from a mistake the player could see
## and avoid. What is not acceptable is a death that was geometrically impossible to avoid.
##
## So every fight is a real one - the same strong build the TTK numbers were measured with, the
## real weapon fire, the authored HP pool, no forced attack, no injected damage, no
## invulnerability - and the interesting output is the escape probe's verdict at the moment of
## death compared with the damage ledger's account of what actually killed the player.
##
## A death is only a balance defect when ALL of these hold:
##   * two or more damaging footprints were live at the same time,
##   * no reachable point stayed outside the set that was allowed to open (the FAIR verdict, so
##     a footprint the fog gate had not yet released cannot be blamed),
##   * and the condition persisted for at least three consecutive samples (0.3 s), so a single
##     frame of physics cannot manufacture it.
##
## Usage:
##   res://tests/B8BossFair.tscn -- stage=30 runs=3 seeds=...,... tag=pre
##   res://tests/B8BossFair.tscn -- stage=40 runs=3 tag=pre

const STAGE_BOSS = {10:"B01",20:"B02",30:"B03",40:"B04"}
const BUDGET_MS := 260000
const EVIDENCE := "res://docs/iteration/evidence/b8"

func fight(stage: int, seed_value: int, tag: String) -> Dictionary:
	stop(); dismiss()
	if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
	configure(124,true)
	PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
	PlayerData.player_hp_max = 8; PlayerData.player_hp = 8
	seed(seed_value)
	reset_telemetry()
	meta = {"stage":stage,"boss":STAGE_BOSS.get(stage,""),"seed":seed_value,"gun":124,
		"pool":8,"tag":tag,"mode":"boss-fair"}
	check(LevelServer.town.depart(stage,true),"boss depart "+str(stage))
	var boss = instance_from_id(LevelServer.boss_instance)
	check(is_instance_valid(boss),"stage %d spawns its boss" % stage)
	var boss_hp_start := 0.0
	if is_instance_valid(boss): boss_hp_start = boss.max_hp
	attach_telemetry()
	shots_fired = 0; movement = 0; last_position = Utils.player.global_position
	target_boss = true; driving = true; moving = true
	var start = Time.get_ticks_msec()
	var truncated := false
	var peak_owned := 0
	while LevelServer.state == "COMBAT":
		await wait(0.05)
		if is_instance_valid(boss):
			peak_owned = maxi(peak_owned,get_tree().get_nodes_in_group("hostile_zone").filter(
				func(z): return z.owner_ref and z.owner_ref.get_ref() == boss).size())
		if Time.get_ticks_msec()-start > BUDGET_MS: truncated = true; break
	var outcome := "truncated"
	if LevelServer.state == "CAMP": outcome = "clear"
	elif Utils.player.is_dead: outcome = "death"
	driving = false
	var result := row(outcome)
	result["truncated"] = truncated
	result["boss_hp_max"] = boss_hp_start
	result["round_ms"] = Time.get_ticks_msec()-start
	result["peak_owned_zones"] = peak_owned
	detach_telemetry()
	check(not truncated,"the boss fight resolves within the budget (stage %d seed %d)" % [stage,seed_value])
	stop(); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
	check(get_tree().get_nodes_in_group("monsters").is_empty(),"boss cleanup "+str(stage))
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"boss stage leaves no hazard "+str(stage))
	check(not ArenaVisibility.fog_active(),"camp is bright after "+str(stage))
	return result

## Turns one row into the brief's verdict, so the report cannot quietly upgrade "the bot got
## hit twice" into "the design is unfair".
static func verdict(row: Dictionary) -> Dictionary:
	var events: Array = row.get("denial_events",[])
	var combo_peak := 0
	for event in events: combo_peak = maxi(combo_peak,int(event.get("modes",[]).size()))
	var snapshot: Dictionary = row.get("death_snapshot",{})
	var zones: Dictionary = snapshot.get("zones",{}) if not snapshot.is_empty() else {}
	var simultaneous := 0
	for key in zones: simultaneous += int(zones[key])
	return {
		"stage":row.get("stage",0),
		"outcome":row.get("outcome",""),
		"seconds":row.get("seconds",0.0),
		"killer":(snapshot.get("lethal",{}).get("tag","") if not snapshot.is_empty() else ""),
		"killer_category":(snapshot.get("lethal",{}).get("category","") if not snapshot.is_empty() else ""),
		"death_phase":(snapshot.get("phase","") if not snapshot.is_empty() else ""),
		"death_boss_action":(snapshot.get("boss_action","") if not snapshot.is_empty() else ""),
		"death_zones":zones,
		"death_hazards":(snapshot.get("hazards",{}) if not snapshot.is_empty() else {}),
		"death_projectiles":(snapshot.get("projectiles",0) if not snapshot.is_empty() else 0),
		"death_fog":(snapshot.get("fog",false) if not snapshot.is_empty() else false),
		"escape_at_death":(snapshot.get("escape",{}) if not snapshot.is_empty() else {}),
		"simultaneous_footprints":simultaneous,
		"denial_streak_peak":row.get("denial_streak_peak",0),
		"denial_events":events.size(),
		"max_combo":combo_peak,
		# The single claim the batch is allowed to act on.
		"unavoidable":(row.get("outcome","") == "death" and int(row.get("denial_streak_peak",0)) >= 3)
	}

func _ready():
	await boot()
	var stage := user_int("stage=",30)
	var tag := user_arg("tag=","pre")
	var seeds := user_seeds([4201,4202,4203])
	var rows := []
	var verdicts := []
	for seed_value in seeds:
		var result := await fight(stage,seed_value,tag)
		rows.append(result)
		verdicts.append(verdict(result))
		print("B8 BOSS ",JSON.stringify(result))
		print("B8 BOSS VERDICT ",JSON.stringify(verdicts[-1]))
	var clears := rows.filter(func(r): return r.outcome == "clear").size()
	var unavoidable := verdicts.filter(func(v): return v.unavoidable).size()
	print("B8 BOSS SUMMARY stage=%d tag=%s runs=%d clears=%d deaths=%d unavoidable=%d" % [
		stage,tag,rows.size(),clears,rows.size()-clears,unavoidable])
	write_json("%s/boss-fair-%s-s%d.json" % [EVIDENCE,tag,stage],{"rows":rows,"verdicts":verdicts})
	write_json("%s/boss-fair-%s-s%d-verdicts.json" % [EVIDENCE,tag,stage],verdicts)
	print("B8 BOSS CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

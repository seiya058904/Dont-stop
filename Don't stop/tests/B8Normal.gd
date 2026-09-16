extends "res://tests/B8Probe.gd"

## B8 Normal Campaign late-game driver.
##
## The build, the weapon, the talents, the upgrades, the HP pool and the DRIVER are the exact
## ones the B批 measurement used and the ones that died on 22 / 26 / 29: gun 117 with the
## `typical` bundle, `M8Runtime._process` unchanged. Nothing in this file raises or lowers the
## player's power to make a round clear.
##
## Two modes, because they answer different questions and must not be conflated:
##
##   mode=baseline   Reproduces last round's run verbatim: the stage sequence in order, in one
##                   process, with PlayerData.player_level left to evolve from kills exactly as
##                   it did then. This is the only mode that is apples-to-apples with the B批
##                   numbers, and it is also what reports the level each stage actually started
##                   at, so the pinned batch below can be configured to the same power.
##
##   mode=batch      One stage, N independent seeds, with player_level PINNED to a declared
##                   value. Independent samples need a configuration that does not drift, and
##                   the level would otherwise climb across the runs of a batch and make run 5 a
##                   different build from run 1. The pinned value is not chosen for effect: it
##                   is the level `mode=baseline` measured at that stage.
##
## Usage:
##   res://tests/B8Normal.tscn -- stages=7,13,17,22,26,29 mode=baseline tag=pre
##   res://tests/B8Normal.tscn -- stage=22 mode=batch seeds=9101,9102,9103,9104,9105 pin_level=3 tag=pre

const TYPICAL_UPGRADES := ["110","0","1","117","120"]
const TYPICAL_TALENTS := {"T01":2,"T02":2,"T03":2,"T04":2,"T07":3,"T08":2,"T19":1,"T24":2}
const TYPICAL_REWARDS := [12,14,17,18,20,21,22,23]
const BUDGET_MS := 62000
const EVIDENCE := "res://docs/iteration/evidence/b8"

func ready_build() -> void:
	Demo.owned_global_upgrades = TYPICAL_UPGRADES.duplicate()
	Demo.talents = TYPICAL_TALENTS.duplicate()
	for id in TYPICAL_REWARDS:
		RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
	Demo.refresh()

## One real round. Returns the telemetry row.
func run_stage(stage: int, seed_value: int, pin_level: int, tag: String) -> Dictionary:
	stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.3)
	PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
	# Pin the level BEFORE configure so player_damage and the pool are the pinned build's.
	if pin_level > 0:
		PlayerData.player_level = pin_level
		PlayerData.player_exp = 0
	configure(117,false)
	PlayerData.player_hp_max = 8; PlayerData.player_hp = 8
	var level_before := int(PlayerData.player_level)
	# Seeded here, after the camp work and immediately before the departure: the roster, the
	# ring positions and the flank arcs are all drawn from the global generator during the
	# round, so this is the one place a sample's randomness is determined. Hazard placement is
	# NOT on this generator (ArenaHazardDirector seeds itself from stage+epoch+808), which is
	# why each run in a sequence also gets a different terrain plan. `seed=0` means "do not
	# re-seed": the sequence keeps consuming the stream exactly as the B批 density run did.
	if seed_value != 0: seed(seed_value)
	reset_telemetry()
	meta = {"stage":stage,"seed":seed_value,"pin_level":pin_level,"level_before":level_before,
		"gun":117,"talents":TYPICAL_TALENTS.duplicate(),"upgrades":TYPICAL_UPGRADES.duplicate(),
		"hp_max":8,"mode":user_arg("mode=","baseline"),"tag":tag}
	check(LevelServer.town.depart(stage,true),"depart stage "+str(stage))
	attach_telemetry()
	movement = 0; shots_fired = 0; last_position = Utils.player.global_position
	driving = true; moving = true; target_boss = false
	var start = Time.get_ticks_msec()
	var truncated := false
	while LevelServer.state == "COMBAT":
		await wait(0.1)
		if Time.get_ticks_msec()-start > BUDGET_MS: truncated = true; break
	var outcome := "truncated"
	if LevelServer.state == "CAMP": outcome = "clear"
	elif Utils.player.is_dead: outcome = "death"
	driving = false
	var result := row(outcome)
	result["truncated"] = truncated
	result["level_after"] = PlayerData.player_level
	result["round_ms"] = Time.get_ticks_msec()-start
	detach_telemetry()
	check(not truncated,"the round resolves within the budget (stage %d seed %d)" % [stage,seed_value])
	# Structural legality, same claim and same zero tolerance tests/M10Density.gd makes.
	check(int(result.illegal_near_spawns) == 0,
		"no monster spawns inside the player's personal space (stage %d seed %d)" % [stage,seed_value])
	stop(); LevelServer.return_to_camp(); await wait(0.4)
	return result

func _ready():
	await boot()
	ready_build()
	var tag := user_arg("tag=","pre")
	var mode := user_arg("mode=","baseline")
	var rows := []
	if mode == "batch":
		var stage := user_int("stage=",22)
		var pin := user_int("pin_level=",0)
		for seed_value in user_seeds([9101,9102,9103,9104,9105]):
			var result := await run_stage(stage,seed_value,pin,tag)
			rows.append(result)
			print("B8 NORMAL ",JSON.stringify(result))
			write_json("%s/normal-%s-s%d.json" % [EVIDENCE,tag,stage],rows)
	else:
		var stages := []
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("stages="):
				for piece in arg.substr(7).split(",",false): stages.append(int(piece))
		if stages.is_empty(): stages = [7,13,17,22,26,29]
		for stage in stages:
			var result := await run_stage(stage,user_int("seed=",0),0,tag)
			rows.append(result)
			print("B8 NORMAL ",JSON.stringify(result))
		write_json("%s/normal-%s-sequence.json" % [EVIDENCE,tag],rows)
	var line := []
	for result in rows:
		line.append("s%d/%s/%s/%.1fs/lv%s" % [result.stage,result.seed,result.outcome,result.seconds,result.level_before])
	print("B8 NORMAL SUMMARY tag=",tag," mode=",mode," ",", ".join(line))
	print("B8 NORMAL CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

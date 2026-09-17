extends "res://tests/B8Normal.gd"

## B9 measurement fixture: the NEW driver against the UNCHANGED product.
##
## The brief for B9 is explicit that the first batch must change exactly one thing - the driver -
## and nothing else. So this file does not re-implement the measurement; it INHERITS it:
##
##   boot()        inherited from M8Runtime
##   ready_build() inherited from B8Normal   (gun 117, the `typical` bundle, 8 HP)
##   run_stage()   inherited from B8Normal   (depart, drive, the 10 Hz probe, row())
##   row()         inherited from B8Probe    (now also carrying the B9 dodge telemetry)
##
## B8Normal.run_stage() is the very function that produced `normal-final-s22/26/29.json` on the
## OLD driver, so running it again on the NEW driver is the tightest available apples-to-apples
## comparison: same build, same weapon, same talents, same upgrades, same 8 HP pool, same seeds,
## same pinned level, same probe, same evidence schema. The only difference between the two
## evidence sets is M8Runtime.choose_safe_movement's call site.
##
## The duplication that remains (mode dispatch, file name, drift guard) is bookkeeping, not
## measurement. FIXTURE_GUARD below is what keeps it honest: if B8Normal's fixture ever drifts,
## this scene fails loudly instead of quietly measuring something else.
##
## Usage (identical semantics to B8Normal):
##   res://tests/B9Normal.tscn -- stage=22 mode=batch seeds=9101,...,9105 pin_level=7 tag=newdriver
##   res://tests/B9Normal.tscn -- stages=21,24,25,27,28 mode=baseline tag=sanity

const B9_EVIDENCE := "res://docs/iteration/evidence/b9"
const FIXTURE_GUARD := "the B9 fixture must stay byte-compatible with the one that produced the B8 numbers"

## The pinned levels B8's own `mode=baseline` measured at these stages, re-stated here so a batch
## cannot silently pin a different build.
const PINNED := {22:7,26:7,29:8}

func fixture_guard() -> void:
	check(TYPICAL_UPGRADES == ["110","0","1","117","120"],FIXTURE_GUARD+": upgrades unchanged")
	check(TYPICAL_TALENTS == {"T01":2,"T02":2,"T03":2,"T04":2,"T07":3,"T08":2,"T19":1,"T24":2},
		FIXTURE_GUARD+": talents unchanged")
	check(TYPICAL_REWARDS == [12,14,17,18,20,21,22,23],FIXTURE_GUARD+": rewards unchanged")
	check(BUDGET_MS == 62000,FIXTURE_GUARD+": round budget unchanged")
	check(DODGE_DIRECTIONS == 16 and is_equal_approx(DODGE_LOOKAHEAD,38.0) and is_equal_approx(DODGE_WALL_STEP,24.0),
		FIXTURE_GUARD+": the core still samples 16 directions at 38 px with a 24 px wall step")

## Refuse to destroy evidence.
##
## Batch mode rewrites its output file after every run with the rows accumulated IN THIS PROCESS,
## so a second invocation with the same tag and stage does not append - it REPLACES the first
## invocation's rows. That is not hypothetical: the second extension of the B9 sanity sweep
## (seeds 9103-9105 at stages 24 and 25, tag `sanity`) silently dropped the seeds 9101-9102 rows
## the first invocation had written. No measurement number was lost from a reported batch (the
## 22/26/29 batches all use distinct tags and were each measured in a single process), but the
## instrument must not be able to do this at all.
##
## The guard runs BEFORE any round, so a refused invocation costs nothing. Pick a new tag.
func guard_output(path: String) -> bool:
	if not FileAccess.file_exists(path): return true
	check(false,"refusing to overwrite existing evidence at "+path+" - re-run with a new tag")
	return false

func _ready():
	await boot()
	ready_build()
	fixture_guard()
	var tag := user_arg("tag=","newdriver")
	var mode := user_arg("mode=","baseline")
	var rows := []
	if mode == "batch":
		var stage := user_int("stage=",22)
		var pin := user_int("pin_level=",PINNED.get(stage,0))
		if not guard_output("%s/normal-%s-s%d.json" % [B9_EVIDENCE,tag,stage]):
			print("B9 NORMAL CHECKS=",checks," FAILURES=",failures)
			get_tree().quit(1)
			return
		for seed_value in user_seeds([9101,9102,9103,9104,9105]):
			var result := await run_stage(stage,seed_value,pin,tag)
			rows.append(result)
			print("B9 NORMAL ",JSON.stringify(result))
			write_json("%s/normal-%s-s%d.json" % [B9_EVIDENCE,tag,stage],rows)
	else:
		var stages := []
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("stages="):
				for piece in arg.substr(7).split(",",false): stages.append(int(piece))
		if stages.is_empty(): stages = [22,26,29]
		if not guard_output("%s/normal-%s-sequence.json" % [B9_EVIDENCE,tag]):
			print("B9 NORMAL CHECKS=",checks," FAILURES=",failures)
			get_tree().quit(1)
			return
		for stage in stages:
			var result := await run_stage(stage,user_int("seed=",0),0,tag)
			rows.append(result)
			print("B9 NORMAL ",JSON.stringify(result))
		write_json("%s/normal-%s-sequence.json" % [B9_EVIDENCE,tag],rows)
	var line := []
	for result in rows:
		line.append("s%d/%s/%s/%.1fs/hits%s/dodge%s" % [result.stage,result.seed,result.outcome,
			result.seconds,result.get("hits_total",0),result.get("dodge_decisions",0)])
	print("B9 NORMAL SUMMARY tag=",tag," mode=",mode," ",", ".join(line))
	print("B9 NORMAL CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

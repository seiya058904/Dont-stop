extends "res://tests/M8Runtime.gd"

## Regression for the manual "完全不掉血" report.
##
## The cause was not the damage formula and not the HUD: Smoke's `--perf` and
## `--stage-tour` rigs raise max HP to 100000 so a long measurement cannot end on a
## level-1 health bar, and because they never armed test mode the round's own
## `return_to_camp()` saved that pool into the player's real camp file. Every later
## normal launch restored `hp_max = 100001`, so incoming damage of a few points moved
## the value by 0.05% and the bar rendered "100%" forever.
##
## This fixture pins both halves of the fix: an already-leaked pool is repaired on
## load, and a live diagnostic pool can no longer reach the save file at all.
func _ready():
	await boot()
	dismiss()

	# 1. A file carrying the leaked pool is still a readable save; it is repaired, not
	#    rejected, because rejecting it would raise the "存档损坏" recovery dialog on a
	#    save the player can otherwise keep using.
	var contaminated := {
		"schema_version":6,"campaign_complete":false,"hell_complete":false,
		"gold":100,"points":0,"reserve_magazines":10,"level":31,"exp":0.0,
		"hp":100001.0,"hp_max":100001.0,"weapons":[],"owned_global_upgrades":[],
		"talents":{},"talent_payments":[],"legacy":[],"legacy_state":{},
		"next_stage":1,"selected_stage":1,"unequipped":false,"equipped":""
	}
	check(CampSnapshot.validate(contaminated),"a leaked-pool save is still a readable file")
	var repaired := CampSnapshot.normalize(contaminated)
	var ceiling := CampSnapshot.hp_max_ceiling(31)
	check(is_equal_approx(float(repaired.hp_max),ceiling),"the leaked pool is clamped to the level's ceiling on load")
	check(float(repaired.hp) <= float(repaired.hp_max),"the repaired current HP stays inside the repaired pool")
	check(ceiling > 56.0,"the ceiling still admits every legitimate build (about 56 at level 40)")
	check(ceiling < 1000.0,"the ceiling rejects a diagnostic pool by orders of magnitude")

	# 2. A legitimate late-game pool is untouched, so the repair cannot nerf a real build.
	var legit := contaminated.duplicate(true)
	legit.hp = 31.0
	legit.hp_max = 56.0
	var kept := CampSnapshot.normalize(legit)
	check(is_equal_approx(float(kept.hp_max),56.0) and is_equal_approx(float(kept.hp),31.0),"a legitimate late-game pool round-trips unchanged")

	# 3. The product cannot persist a diagnostic pool even while one is live.
	PlayerData.player_hp_max = 100000.0
	PlayerData.player_hp = 100000.0
	var written := Demo.snapshot()
	check(float(written.hp_max) <= ceiling,"snapshot clamps a live diagnostic pool before it can reach the save file")
	check(float(written.hp) <= float(written.hp_max),"the clamped snapshot keeps HP inside its pool")

	# 4. End to end: with a reachable pool the HUD's own percentage moves on a real hit.
	var ui = Utils.canvasLayer.get_node("GameUI")
	var bar: ProgressBar = ui.get_node("hpUI/ProgressBar")
	Demo.talents = {}
	Demo.talent_cooldowns = {}
	LevelServer.state = "COMBAT"
	get_tree().paused = false
	Utils.player.is_dead = false
	PlayerData.player_hp_max = 56
	PlayerData.player_hp = 56
	await get_tree().process_frame
	var pct_before := int(round(bar.value / bar.max_value * 100.0))
	Utils.player.onHit(8.0,null,1.0,"p0-save-sanity")
	await get_tree().process_frame
	var pct_after := int(round(bar.value / bar.max_value * 100.0))
	check(PlayerData.player_hp < 56.0,"a real hit lowers a reachable pool")
	check(pct_after < pct_before,"the rendered percentage moves once the pool is reachable")

	print("P0_SAVE_SANITY ",JSON.stringify({"ceiling":ceiling,"repaired_hp_max":repaired.hp_max,
		"written_hp_max":written.hp_max,"pct_before":pct_before,"pct_after":pct_after,
		"hp_after":PlayerData.player_hp}))
	print("P0_SAVE_SANITY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

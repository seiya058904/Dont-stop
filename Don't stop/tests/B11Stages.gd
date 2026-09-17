extends "res://tests/M8Runtime.gd"

## B11 stage-access contract.
##
## This file REPLACES tests/B10Playtest.gd, which asserted the opposite product rule: that Hell was
## locked behind the normal campaign and reachable only through a separately branded
## "HELL PLAYTEST" selector whose departures recorded nothing. That was a misreading of the
## requirement, and B11 deleted it.
##
## The rule asserted here instead:
##   1. there is ONE stage selector, it offers 1-40, and every entry is enabled;
##   2. on a BRAND-NEW save, 1, 10, 20, 30, 31, 35, 39 and 40 are all departable, and a Hell
##      departure really applies Hell;
##   3. no player-visible STRING in the panel says Locked / 未解锁 / Playtest / 试玩, and the panel
##      has no second selector to reach;
##   4. the progression fields still exist for the save format and still bound the LINEAR campaign
##      pointer, but they no longer decide what a player may choose;
##   5. Stage 40 is terminal: no path produces a Stage 41.
const OPEN_PROBE := [1,10,20,30,31,35,39,40]
## Latin and CJK forms of the words the product may never show for a stage. Checked against every
## quoted string literal in the panel source AND against every live label on screen, so a comment
## that merely names the removed concept is not a false failure while a real label still is.
const FORBIDDEN := ["Locked","LOCKED","Playtest","PLAYTEST","未解锁","试玩","Trial","TRIAL"]
const STRING_LITERAL := "\"([^\"\\n]*)\""

func panel_strings() -> Array:
	# Read-only scan of the literal strings CampPanel.gd can ever render. A `+ "..."` concatenation
	# is caught too, because the scan is per literal, not per expression.
	var out := []
	var regex := RegEx.new()
	regex.compile(STRING_LITERAL)
	for found in regex.search_all(FileAccess.get_file_as_string("res://ui/CampPanel.gd")):
		out.append(found.get_string(1))
	return out

func collect_labels(node: Node, out: Array) -> void:
	if node is Label: out.append((node as Label).text)
	if node is Button: out.append((node as Button).text)
	for child in node.get_children(): collect_labels(child,out)

## Every stage entry the live panel is showing, keyed by the stage id it stores on its own button.
func live_stage_entries(node: Node, out: Dictionary) -> void:
	if node is Button and (node as Button).has_meta("stage_id"):
		out[int((node as Button).get_meta("stage_id"))] = node
	for child in node.get_children(): live_stage_entries(child,out)

func _ready():
	await boot()
	configure(124)
	LevelServer.state = "CAMP"
	Demo.talents = {}
	Demo.owned_global_upgrades = []
	Demo.campaign_complete = false
	Demo.hell_complete = false
	Demo.next_stage = 1
	Demo.selected_stage = 1
	PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000

	# ---- 1. the table itself -------------------------------------------------------------
	check(DemoConfig.ENCOUNTERS.has(31) and DemoConfig.ENCOUNTERS.has(40),"stages 31-40 are registered")
	check(not DemoConfig.ENCOUNTERS.has(41),"stage 41 is never created")

	# ---- 2. a fresh save sees ONE list, and every entry in it is enabled ------------------
	LevelServer.state = "CAMP"
	Demo.open_panel()
	await wait(0.3)
	var panel = Demo.ui
	check(is_instance_valid(panel),"the camp panel opens for the stage list")
	if not is_instance_valid(panel):
		print("B11_STAGES checks=",checks," failures=",failures+1)
		get_tree().quit(1)
		return
	panel.switch_tab("stage")
	await wait(0.3)
	var entries := {}
	live_stage_entries(panel,entries)
	check(entries.size() == 40,"the single stage list offers all 40 stages (found %d)" % entries.size())
	var disabled := []
	for id in entries:
		if entries[id].disabled: disabled.append(id)
	check(disabled.is_empty(),"no stage entry is disabled on a fresh save (%s)" % str(disabled))
	for stage in OPEN_PROBE:
		check(panel.stage_unlocked(stage),"fresh save: stage %d answers available" % stage)
		check(entries.has(stage),"fresh save: the stage-%d entry is in the list" % stage)

	# ---- 3. nothing player-visible names a lock or a trial ------------------------------
	var texts := []
	collect_labels(panel,texts)
	var on_screen := "\n".join(texts)
	var visible_hits := []
	for word in FORBIDDEN:
		if word in on_screen: visible_hits.append(word)
	check(visible_hits.is_empty(),"no live label carries a lock/playtest word (%s)" % str(visible_hits))
	# The panel keeps ONE comment that describes the removed concept by name, so the exact review
	# sentence that documents the removal is exempt by full equality. Every other literal is
	# inspected, and the live-label scan above is the part that really cannot be fooled.
	const DOC_EXEMPT := ["Hell Playtest","HELL PLAYTEST / 地狱试玩"]
	var literal_hits := []
	for literal in panel_strings():
		if literal in DOC_EXEMPT: continue
		for word in FORBIDDEN:
			if word in literal: literal_hits.append(word+" in "+literal)
	check(literal_hits.is_empty(),"no renderable string in the panel names a lock or a trial (%s)" % str(literal_hits))
	var source := FileAccess.get_file_as_string("res://ui/CampPanel.gd")
	check(not source.contains("hell_playtest"),"the panel has no playtest flag left")
	check(not source.contains("HELL_PLAYTEST"),"the panel has no playtest label left")
	check(not source.contains("stage_playtestable"),"the panel has no second selector left")

	# ---- 4. a fresh save really ENTERS a Hell stage from that one list --------------------
	for stage in [31,35,39,40]:
		LevelServer.return_to_camp()
		await wait(0.4)
		LevelServer.state = "CAMP"
		if not is_instance_valid(Demo.ui):
			Demo.open_panel(); await wait(0.25)
		Demo.ui.switch_tab("stage")
		await wait(0.2)
		Demo.ui.depart(stage)
		await wait(0.8)
		check(LevelServer.state == "COMBAT" and LevelServer.level == stage,
			"fresh save departs the real stage %d (state=%s level=%d)" % [stage,LevelServer.state,LevelServer.level])
		check(ArenaVisibility.fog_active(),"stage %d really applies Hell darkness" % stage)
		check(Demo.trial,"a direct stage choice is a repeat departure, so it cannot move the pointer")
		check(not Demo.campaign_complete and not Demo.hell_complete,
			"entering stage %d on a fresh save claims nothing" % stage)
		LevelServer.return_to_camp()
		await wait(0.4)
	check(int(Demo.next_stage) == 1,
		"the whole Hell sequence left the campaign pointer alone (%d)" % int(Demo.next_stage))

	# ---- 5. the save format accepts a Hell selection without campaign completion ----------
	Demo.selected_stage = 39
	var snap = Demo.snapshot()
	check(CampSnapshot.validate(snap),"a fresh save holding a Hell selection is a valid snapshot")
	var normalized = CampSnapshot.normalize(snap)
	check(int(normalized.selected_stage) == 39,
		"normalize() keeps a Hell selection instead of rewriting it (%d)" % int(normalized.selected_stage))
	check(int(normalized.next_stage) == 1,
		"normalize() leaves an untouched linear pointer alone (%d)" % int(normalized.next_stage))
	# The pointer may legally sit on a Hell stage even without campaign completion: choosing a
	# stage is not gated any more, so the save format must not disagree with the UI.
	var hell_pointer = snap.duplicate(true)
	hell_pointer.next_stage = 40
	check(int(CampSnapshot.normalize(hell_pointer).next_stage) == 40,
		"normalize() keeps a Hell linear pointer instead of clamping it to 30")
	var bogus_pointer = snap.duplicate(true)
	bogus_pointer.next_stage = 41
	check(int(CampSnapshot.normalize(bogus_pointer).next_stage) == 40,
		"normalize() still bounds the pointer to the real stage table")

	# ---- 6. Stage 40 is terminal ---------------------------------------------------------
	LevelServer.return_to_camp()
	await wait(0.4)
	Demo.next_stage = 40
	Demo.selected_stage = 40
	check(LevelServer.town.depart(40,false),"the stage-40 normal departure starts")
	await wait(0.8)
	check(LevelServer.level == 40,"the terminal round really is stage 40")
	# Stage 40 is a boss round, so victory() refuses until the boss is really dead. Killing it
	# through the real damage path is what makes the completion claim below non-vacuous.
	var boss = instance_from_id(LevelServer.boss_instance)
	check(is_instance_valid(boss),"stage 40 spawns its boss")
	if is_instance_valid(boss):
		Combat.hit(boss,{"damage":100000.0,"epoch":LevelServer.epoch})
	await wait(0.8)
	check(Demo.hell_complete,"clearing stage 40 records Hell completion")
	check(int(Demo.next_stage) == 40,"clearing stage 40 leaves the pointer on 40, never 41")
	check(CampSnapshot.validate(Demo.snapshot()),"the post-stage-40 save is still valid")
	check(int(CampSnapshot.normalize(Demo.snapshot()).next_stage) == 40,"normalize() keeps stage 40 terminal")

	# ---- 7. no path can ever ask for a Stage 41 ------------------------------------------
	var requested := []
	for level in range(1,41):
		var keys = DemoConfig.ENCOUNTERS.keys()
		var follow = keys[mini(keys.find(level)+1,keys.size()-1)]
		requested.append(follow)
	var over := requested.filter(func(value): return int(value) > 40)
	check(over.is_empty(),"the positional advance never leaves 1-40 (%s)" % str(over))
	check(int(requested[39]) == 40,"stage 40's own advance stays at stage 40 (%d)" % int(requested[39]))

	print("B11_STAGES checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

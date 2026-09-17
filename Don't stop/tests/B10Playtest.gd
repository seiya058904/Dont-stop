extends "res://tests/M3Weapons.gd"

## B10 Hell playtest access contracts.
##
## WHY THIS SCENE EXISTS
## ---------------------
## Stage 31-40 shipped, were balanced and were never playable by a human. The formal gate is
## `Demo.campaign_complete`, and the only bypass was the native `--hell-unlock` command-line
## flag, which `web/loader.html` never maps from a query parameter. So the first real playtest
## of Hell could not happen at all.
##
## The fix adds a visibly labelled playtest selector to the camp stage list. That is a change to
## the way a player can ENTER the game, which is exactly the kind of change that must not be
## allowed to leak into progression - so every claim it rests on is asserted here, on real
## product code, in seconds, before any browser run:
##
##   1. the FORMAL gate is unchanged: 31-40 still refuse a fresh save, at the UI lock AND at
##      depart(), and `--hell-unlock` still works for the suites that already rely on it;
##   2. the playtest path is CLOSED until the visible entry is used, and it only ever opens
##      Hell stages;
##   3. a playtest departure really enters the stage, with the Hell darkness really applied;
##   4. WINNING a playtest round writes NO progression: next_stage, campaign_complete and
##      hell_complete are all untouched, including at Stage 40 - the playtest cannot fake a
##      completion or move the campaign pointer;
##   5. a save written after a playtest is still a state the product accepts, and
##      `CampSnapshot.normalize()` is a no-op on it (a playtest must not write a state the
##      loader would have to repair);
##   6. the probe's copied labels still match the panel's constants, so the browser driver
##      cannot silently start clicking a label the product no longer renders.

const CAMP := preload("res://ui/CampPanel.gd")
const BUDGET_MS := 90000
## Prefix for the claims that are the whole point of the round: the playtest may not touch
## progression. Kept in one place so those failures are greppable as a group.
const FIXTURE := "[playtest must not touch progression] "

var panel: Node

## Names whatever is holding the pause stack, so a frozen round can name its own cause.
func _stack_names() -> String:
	var out := []
	for node in Demo.pause_stack:
		if not is_instance_valid(node): out.append("<freed>"); continue
		var script: Variant = node.get_script()
		out.append((script as Script).resource_path if script != null else str(node))
	return ",".join(out)

func dismiss() -> void:
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()

## Open the camp panel on the stage tab, the way a player reaches the list.
##
## Note the wait loop. A Control that has been `queue_free()`d is still `is_instance_valid()`
## until the frame in which the engine actually deletes it, so calling `Demo.open_panel()` too
## early makes it early-return - the handle it guards still looks alive - and the panel it hands
## back is the outgoing, about-to-be-deleted one. Waiting for the handle to really die first is
## what makes "close the panel, play another stage, close it again" work repeatedly, which is
## exactly the flow a reviewer walks.
func open_stage_list() -> bool:
	LevelServer.state = "CAMP"
	var guard := 0
	while is_instance_valid(Demo.ui) and guard < 60:
		Demo.ui.queue_free()
		await get_tree().process_frame
		guard += 1
	Demo.open_panel()
	await wait(0.3)
	if not is_instance_valid(Demo.ui): return false
	panel = Demo.ui
	panel.switch_tab("stage")
	await wait(0.25)
	return true

## Close the panel so the next departure starts clean, the way closing it does in game.
## A coroutine: callers must `await` it, or the next open races the deletion.
func close_panel() -> void:
	if is_instance_valid(panel): panel.queue_free()
	panel = null
	await wait(0.2)

## One real playtest round: depart through the visible selector, resolve the round, come back
## to camp. `resolve` says how it ends:
##   "timer" an ordinary stage - the round clock is dropped to zero, the route
##           tests/M5World.gd uses for a non-boss encounter;
##   "boss"  a boss stage - the boss is killed through the real damage funnel;
##   "none"  observe the departure only.
## Returns the progression readings taken around the round.
func playtest_round(stage: int, resolve: String) -> Dictionary:
	var before = {"next":int(Demo.next_stage),"campaign":Demo.campaign_complete,
		"hell":Demo.hell_complete,"selected":int(Demo.selected_stage)}
	if not await open_stage_list():
		check(false,"the camp panel opens for stage %d" % stage)
		return before
	panel.hell_playtest = true
	panel.depart(stage,true,true)
	await wait(0.7)
	before["state"] = LevelServer.state
	before["level"] = LevelServer.level
	before["trial"] = Demo.trial
	before["marked"] = Demo.hell_playtest_stage
	before["fog"] = ArenaVisibility.fog_active()
	before["paused"] = get_tree().paused
	before["panels"] = Demo.pause_stack.size()
	before["stack"] = _stack_names()
	# LIVENESS, and this is the reading that makes every other one here mean something. No single
	# signal covers both kinds of stage, because they are built differently:
	#   * an ordinary stage counts down, so its round clock advancing proves the round runs;
	#   * a BOSS stage has `seconds: 0` by design ("无倒计时自动胜利"), so its clock is pinned at
	#     zero and can never advance - and it spawns no horde either (its `roles` is empty), so
	#     its director counter stays at zero too. What DOES change is the boss itself: its own
	#     action counter only moves while its AI is being ticked.
	# Any one of those advancing is proof the simulation is really running, and none of them can
	# advance while something owns the pause stack. Without this, "the playtest entered stage 40"
	# is satisfied by a stage number on a frozen tree.
	var boss = instance_from_id(LevelServer.boss_instance)
	var clock_a := float(LevelServer.level_time)
	var index_a := int(LevelServer.spawn_index)
	var boss_a := int(boss.actions.get("attack",0)) if is_instance_valid(boss) else 0
	var live := false
	var live_signal := ""
	for i in 120:
		await wait(0.1)
		if float(LevelServer.level_time) < clock_a: live = true; live_signal = "round clock"; break
		if int(LevelServer.spawn_index) > index_a: live = true; live_signal = "horde spawn"; break
		if is_instance_valid(boss) and int(boss.actions.get("attack",0)) > boss_a:
			live = true; live_signal = "boss action"; break
	before["live"] = live
	before["live_signal"] = live_signal
	before["monsters"] = get_tree().get_nodes_in_group("monsters").size()
	before["boss"] = is_instance_valid(boss)
	if resolve == "timer":
		LevelServer.level_time = 0.01
		LevelServer._timeout()
	elif resolve == "boss" and is_instance_valid(boss):
		Combat.hit(boss,{"damage":100000.0,"epoch":LevelServer.epoch})
	var start = Time.get_ticks_msec()
	while LevelServer.state == "COMBAT" and Time.get_ticks_msec()-start < BUDGET_MS:
		await wait(0.1)
	before["seconds"] = (Time.get_ticks_msec()-start)/1000.0
	before["state_after"] = LevelServer.state
	before["player_dead"] = Utils.player.is_dead
	before["hp_after"] = float(PlayerData.player_hp)
	before["boss_die"] = is_instance_valid(boss) and boss.is_die
	before["boss_freed"] = not is_instance_valid(boss)
	before["camp"] = LevelServer.state == "CAMP"
	before["fog_after"] = ArenaVisibility.fog_active()
	before["next_after"] = int(Demo.next_stage)
	before["campaign_after"] = Demo.campaign_complete
	before["hell_after"] = Demo.hell_complete
	before["selected_after"] = int(Demo.selected_stage)
	before["snapshot"] = Demo.snapshot()
	# A resolved round leaves the product's own results panel on the pause stack, and a paused
	# tree refuses damage AND refuses to spawn. Clearing it is not test convenience: without it
	# the NEXT round departs successfully and then sits frozen - which is exactly the trap the
	# first version of this scene fell into. It reported 31/32/35/38 as "played in turn" while
	# three of those rounds never ran a single simulation tick, because the stage-31 scoreboard
	# still owned the pause stack.
	dismiss()
	await wait(0.4)
	before["unpaused_after"] = not get_tree().paused
	await close_panel()
	return before

func _ready():
	Demo.test_mode = true; seed(1010)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.5)
	Demo.try_purchase("weapon","117")
	PlayerData.player_hp_max = 9000; PlayerData.player_hp = 9000
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	var bypass := "--hell-unlock" in OS.get_cmdline_user_args()

	# ---- 1. the probe's copied labels cannot rot ------------------------------------------
	var smoke_src := FileAccess.get_file_as_string("res://autoload/Smoke.gd")
	check(CAMP.HELL_PLAYTEST_ENTER == "HELL PLAYTEST",FIXTURE+"the playtest entry label is the one the UI renders")
	check(CAMP.HELL_PLAYTEST_EXIT == "退出试玩",FIXTURE+"the playtest exit label is the one the UI renders")
	check(smoke_src.contains('"'+CAMP.HELL_PLAYTEST_ENTER+'"'),
		FIXTURE+"the read-only probe looks for the playtest entry by its real label")
	check(smoke_src.contains('"'+CAMP.HELL_PLAYTEST_EXIT+'"'),
		FIXTURE+"the read-only probe looks for the playtest exit by its real label")

	# ---- 2. a fresh save: the formal gate is exactly as strict as before -------------------
	Demo.campaign_complete = false; Demo.hell_complete = false
	Demo.next_stage = 12; Demo.selected_stage = 12
	check(await open_stage_list(),"the camp panel opens on the stage list")
	check(panel.hell_playtest == false,"the playtest selector starts CLOSED")
	for stage in [31,35,40]:
		if bypass:
			check(panel.stage_unlocked(stage),"the explicit --hell-unlock bypass still opens stage %d" % stage)
		else:
			check(not panel.stage_unlocked(stage),FIXTURE+"the formal gate still refuses stage %d on a fresh save" % stage)
		check(not panel.stage_playtestable(stage),"and the playtest path is shut until the entry is used (stage %d)" % stage)
	check(not panel.stage_playtestable(30),"the playtest path never covers a Normal stage")
	if not bypass:
		# The complaint this round started from: a greyed-out button is not a guard, because
		# the per-stage "开始此遭遇" control is itself a trial departure. It must refuse in code.
		panel.depart(40,true)
		await wait(0.3)
		check(LevelServer.state == "CAMP","a formally locked Hell stage still cannot be departed into")
	# ---- 3. the selector opens ONLY Hell, and only its own stages -------------------------
	panel.hell_playtest = true
	await wait(0.1)
	check(panel.stage_playtestable(31) and panel.stage_playtestable(35) and panel.stage_playtestable(40),
		"the open playtest selector makes every Hell stage departable")
	check(not panel.stage_playtestable(30) and not panel.stage_playtestable(29),
		"and it opens nothing outside 31-40")
	check(panel.stage_unlocked(31) == (Demo.campaign_complete or bypass),
		FIXTURE+"opening the selector does not change the formal gate's own answer")
	await close_panel()

	# ---- 4. a real playtest round, WON, writes no progression ------------------------------
	var first = await playtest_round(31,"timer")
	check(first.state == "COMBAT" and int(first.level) == 31,
		"the playtest entry really departs stage 31 (%s at %s)" % [first.state,first.level])
	check(not first.paused and first.live,FIXTURE+
		"the stage-31 playtest round really RUNS: nothing owns the pause stack (%s) and the round clock advanced" % first.stack)
	check(first.trial,"a playtest departure is a TRIAL departure, which is what keeps it out of the campaign")
	check(int(first.marked) == 31,"the round is marked as a stage-31 playtest")
	check(first.fog,"Hell darkness is really applied during the playtest round")
	check(first.camp,"the playtest round resolves back to camp")
	check(not first.fog_after,"camp is bright again after the playtest round")
	check(first.unpaused_after,"the results panel a finished round shows is cleared, so the next round can run")
	check(int(first.next_after) == int(first.next),FIXTURE+
		"winning a playtest round does not move the campaign pointer (%d -> %d)" % [first.next,first.next_after])
	check(first.campaign_after == first.campaign,FIXTURE+"winning a playtest round does not complete the campaign")
	check(first.hell_after == first.hell,FIXTURE+"winning a playtest round does not claim Hell completion")

	# ---- 5. the same at Stage 40, the stage that WOULD set hell_complete -------------------
	var last = await playtest_round(40,"boss")
	print("B10 ROUND40 ",JSON.stringify(last))
	check(last.state == "COMBAT" and int(last.level) == 40,
		"a playtest reaches stage 40 (%s at %s)" % [last.state,last.level])
	check(last.fog,"stage 40's darkness is applied in the playtest too")
	check(not last.paused and last.live,FIXTURE+"the stage-40 playtest round really runs - proof: %s" % last.live_signal)
	check(last.boss,"stage 40 spawns its boss inside the playtest entry")
	check(last.camp,"clearing the stage-40 playtest resolves normally (state=%s after %.1fs, player_dead=%s, hp=%.1f, paused=%s, panels=%d, stack=%s, monsters=%d)" % [
		last.state_after,last.seconds,last.player_dead,last.hp_after,last.paused,last.panels,last.stack,last.monsters])
	# A boss stage can reach CAMP by exactly one route: victory() - and victory() refuses while
	# the boss is alive or while boss_instance is 0. So the round resolving IS the proof that the
	# real damage funnel killed it. `boss_die` alone would not be: the boss node is freed as it
	# dies, and a freed node reports is_die as false.
	check(last.boss_die or last.boss_freed,FIXTURE+
		"the stage-40 playtest round was ended by the boss actually dying (boss_die=%s, node freed=%s), so the completion claim below is not vacuous" % [last.boss_die,last.boss_freed])
	check(not Demo.hell_complete,FIXTURE+"clearing Stage 40 in playtest does NOT set hell_complete")
	check(int(Demo.next_stage) == int(last.next),FIXTURE+"and it does not move next_stage (%d -> %d)" % [last.next,Demo.next_stage])
	check(not Demo.campaign_complete,FIXTURE+"and it does not complete the campaign")
	check(Demo.hell_playtest_stage == 40,"the stage-40 playtest round is marked as such")

	# ---- 6. consecutive playtests, the flow the reviewer has to walk -----------------------
	var seen := []
	for stage in [31,32,35,38]:
		var round_result = await playtest_round(stage,"timer")
		seen.append([stage,round_result.state,int(round_result.level),round_result.fog,
			not round_result.paused,round_result.live])
	check(seen.all(func(entry): return entry[1] == "COMBAT" and entry[2] == entry[0] and entry[3] and entry[4] and entry[5]),
		"31 / 32 / 35 / 38 can each be played in turn, each one really running with darkness applied: %s" % str(seen))
	check(int(Demo.next_stage) == int(last.next),"the whole playtest sequence left next_stage untouched")

	# ---- 7. a save written after a playtest is still a save the product accepts ------------
	var snap = Demo.snapshot()
	check(CampSnapshot.validate(snap),FIXTURE+"a snapshot taken after a playtest is a state the product accepts")
	check(int(snap.selected_stage) <= 30,
		"the snapshot clamps a Hell selection while the campaign is unfinished (selected=%d)" % int(snap.selected_stage))
	var norm = CampSnapshot.normalize(snap)
	check(int(norm.selected_stage) == int(snap.selected_stage) and int(norm.next_stage) == int(snap.next_stage),
		FIXTURE+"normalize() is a no-op on what snapshot() writes, so nothing has to be repaired on load")
	check(not norm.campaign_complete and not norm.hell_complete,"and the reloaded save claims no completion")
	# An old save must still load unchanged: the playtest added no field to the format.
	check(snap.schema_version == 6,"the save schema is still version 6 - no namespace change")
	var legacy_shape = snap.duplicate(true); legacy_shape.erase("hell_complete")
	check(CampSnapshot.validate(legacy_shape),"a save without hell_complete still validates")

	# ---- 8. a normal departure is not marked as a playtest --------------------------------
	Demo.next_stage = 12
	check(await open_stage_list(),"the camp panel opens again")
	check(panel.hell_playtest == false,"reopening the panel starts the selector closed again")
	panel.depart(12,true)
	await wait(0.6)
	check(LevelServer.state == "COMBAT" and int(LevelServer.level) == 12,"a normal trial departure still works")
	check(Demo.hell_playtest_stage == 0,"a non-playtest departure clears the playtest marker")
	check(not ArenaVisibility.fog_active(),"and a Normal stage carries no darkness")
	await close_panel()

	dismiss(); await wait(0.3)
	print("B10 PLAYTEST CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

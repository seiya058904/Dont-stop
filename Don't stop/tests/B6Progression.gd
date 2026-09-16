extends "res://tests/M8Runtime.gd"

## B6 progression and save-migration audit.
##
## Covers the three rules the user set for this batch:
##   1. a save that finished the normal campaign but predates Hell Mode must migrate from
##      next_stage 30 to 31, WITHOUT losing the recorded Stage-30 completion;
##   2. a save that has NOT finished Stage 30 must not be handed Hell Mode by any path;
##   3. Stage 40 must not produce a Stage 41, and no schema_version bump or namespace change
##      may be needed to express any of it.
##
## The migration is exercised as the pure function it is (CampSnapshot.normalize), because
## that is the exact code path Demo.load_camp() runs between validate() and the restore.

func old_save(campaign: bool, next_stage: int, selected: int) -> Dictionary:
	var snap = Demo.snapshot()
	snap.campaign_complete = campaign
	snap.next_stage = next_stage
	snap.selected_stage = selected
	return snap

func _ready():
	await boot()
	configure(124,true)
	print("B6 mode=",("bypass" if "--hell-unlock" in OS.get_cmdline_user_args() else "product"))

	# --- Table shape -------------------------------------------------------------------
	check(DemoConfig.ENCOUNTERS.has(31) and DemoConfig.ENCOUNTERS.has(40),"stages 31-40 are registered")
	check(not DemoConfig.ENCOUNTERS.has(41),"stage 41 is never created")
	var keys = DemoConfig.ENCOUNTERS.keys()
	var contiguous = true
	for i in range(1,41):
		if not keys.has(i): contiguous = false
	check(contiguous and keys.size()==40,"the campaign is a contiguous 1..40 with no holes")
	# Story order matters: LevelServer.victory() advances by table position.
	check(keys.find(30) < keys.find(31) and keys.find(40)==keys.size()-1,"stage order keeps 30 before 31 and 40 last")

	# --- Rule 1: completed campaign at 30 migrates to 31 --------------------------------
	var done = old_save(true,30,30)
	check(CampSnapshot.validate(done),"a completed-campaign save written before this batch still validates")
	var migrated = CampSnapshot.normalize(done)
	check(int(migrated.next_stage)==31,"completed campaign migrates next_stage 30 -> 31")
	check(migrated.campaign_complete,"the migration keeps the recorded Stage-30 completion")
	check(int(migrated.schema_version)==6,"migration needs no schema_version bump")
	check(not migrated.hell_complete,"a migrated save does not claim Hell completion")
	check(CampSnapshot.validate(migrated),"the migrated save is itself valid")

	# --- Rule 2: an unfinished save is never given Hell ---------------------------------
	for next_value in [30,31,35,40]:
		var pending = old_save(false,next_value,next_value)
		var guarded = CampSnapshot.normalize(pending)
		check(int(guarded.next_stage)<=30 and not guarded.campaign_complete,
			"unfinished save at next_stage %d cannot hold a Hell stage" % next_value)
		check(int(guarded.selected_stage)<=30,"unfinished save cannot select a Hell stage (%d)" % next_value)

	# --- Rule 3: Stage 40 is terminal ---------------------------------------------------
	var cleared = old_save(true,40,40)
	cleared.hell_complete = true
	var terminal = CampSnapshot.normalize(cleared)
	check(int(terminal.next_stage)==40,"a cleared Stage 40 still points at Stage 40")
	check(terminal.hell_complete,"Hell completion survives normalization")

	# --- Optional field: old saves still load -------------------------------------------
	var legacy_shape = done.duplicate(true)
	legacy_shape.erase("hell_complete")
	check(CampSnapshot.validate(legacy_shape),"a save without hell_complete validates unchanged")
	check(not CampSnapshot.normalize(legacy_shape).hell_complete,"a missing hell_complete defaults to false")

	# --- The UI lock is the visible half of the same rule -------------------------------
	LevelServer.state = "CAMP"
	Demo.open_panel()
	await wait(0.25)
	var panel = Demo.ui
	check(is_instance_valid(panel),"the camp panel opens for the stage list")
	if is_instance_valid(panel):
		var bypass = "--hell-unlock" in OS.get_cmdline_user_args()
		for stage in [30]:
			check(panel.stage_unlocked(stage),"stage %d is always open" % stage)
		for stage in [31,35,40]:
			if Demo.campaign_complete:
				check(panel.stage_unlocked(stage),"a completed campaign opens stage %d" % stage)
			elif bypass:
				check(panel.stage_unlocked(stage),"the explicit --hell-unlock bypass opens stage %d" % stage)
			else:
				check(not panel.stage_unlocked(stage),"stage %d stays locked for a fresh save" % stage)
		# The whole complaint was that the per-stage "开始此遭遇" button is itself a trial
		# departure, so a locked entry must refuse at depart() too, not only be greyed out.
		if not Demo.campaign_complete and not bypass:
			panel.switch_tab("stage")
			await wait(0.2)
			panel.depart(40,true)
			await wait(0.1)
			check(LevelServer.state=="CAMP","a locked Hell stage cannot be departed into")
		panel.queue_free()
	await wait(0.2)

	# --- Story completion through the real victory path ---------------------------------
	Demo.campaign_complete = false
	Demo.hell_complete = false
	# Town.depart(stage,false) departs Demo.next_stage, not the stage argument, so the
	# progression counter has to point at Stage 30 for this to be the real stage-30 clear.
	Demo.next_stage = 30
	check(LevelServer.town.depart(30,false),"final normal battle departs")
	await wait(0.6)
	var boss = instance_from_id(LevelServer.boss_instance)
	check(is_instance_valid(boss),"stage 30 spawns its boss")
	check(LevelServer.level == 30,"the normal final battle really is stage 30")
	if is_instance_valid(boss):
		Combat.hit(boss,{"damage":100000.0,"epoch":LevelServer.epoch})
	await wait(0.6)
	check(Demo.campaign_complete,"clearing Stage 30 sets campaign_complete")
	check(int(Demo.next_stage)==31,"clearing Stage 30 unlocks Stage 31")
	check(not Demo.hell_complete,"clearing Stage 30 does not claim Hell completion")
	dismiss(); await wait(0.3)

	print("B6 CHECKSUM checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

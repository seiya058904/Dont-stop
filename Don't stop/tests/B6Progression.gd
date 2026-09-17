extends "res://tests/M8Runtime.gd"

## B6 progression and save-migration audit.
##
## Covers the rules that still hold after B11:
##   1. a save that finished the normal campaign but predates Hell Mode must migrate from
##      next_stage 30 to 31, WITHOUT losing the recorded Stage-30 completion;
##   2. the stage table bounds every saved pointer (1-40) and normalization never invents a
##      completion -- progression no longer gates which stage a player may choose, so the old
##      "an unfinished save can never hold a Hell stage" rule is deliberately gone (see B11Stages);
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

	# --- Rule 2 (B11): the stage TABLE bounds a save; progress does not --------------------
	# The previous batch asserted that an unfinished save could never hold a Hell stage. B11 removed
	# that rule: every stage is permanently choosable, so a Hell stage in `selected_stage` is a state
	# the product must accept rather than quietly rewrite. What still has to hold is that no save may
	# point outside the real 1-40 table, and that normalizing is never a progression write.
	for next_value in [30,31,35,40]:
		var pending = old_save(false,next_value,next_value)
		var guarded = CampSnapshot.normalize(pending)
		check(not guarded.campaign_complete,
			"normalizing an unfinished save never invents a completion (next=%d)" % next_value)
		check(int(guarded.next_stage)==next_value,
			"normalizing keeps a legal linear pointer (%d -> %d)" % [next_value,int(guarded.next_stage)])
		check(int(guarded.selected_stage)==next_value,
			"normalizing keeps a legal Hell selection (%d -> %d)" % [next_value,int(guarded.selected_stage)])
	for out_of_range in [0,41,99]:
		var bogus = old_save(false,out_of_range,out_of_range)
		var clamped = CampSnapshot.normalize(bogus)
		check(int(clamped.next_stage)>=1 and int(clamped.next_stage)<=40,
			"a pointer outside the table is clamped into it (%d -> %d)" % [out_of_range,int(clamped.next_stage)])
		check(int(clamped.selected_stage)>=1 and int(clamped.selected_stage)<=40,
			"a selection outside the table is clamped into it (%d -> %d)" % [out_of_range,int(clamped.selected_stage)])

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

	# --- B11: the stage list has no lock for this to be the visible half of ------------------
	# The panel's own gate is asserted in tests/B11Stages.gd, including a live scan of every label it
	# renders. What belongs HERE is the save-side half: the pointer and the selection stay inside the
	# stage table on every path, and a fresh save can be given a Hell selection.
	var fresh_hell = old_save(false,1,39)
	check(CampSnapshot.validate(fresh_hell),"a fresh save with a Hell selection validates")
	check(int(CampSnapshot.normalize(fresh_hell).selected_stage)==39,
		"a fresh save with a Hell selection survives normalization")
	var fresh_pointer = old_save(false,40,1)
	check(int(CampSnapshot.normalize(fresh_pointer).next_stage)==40,
		"a fresh save may hold any legal pointer, including a Hell one")
	if is_instance_valid(Demo.ui):
		check(Demo.ui.stage_unlocked(40),"the live panel answers available for stage 40")
		Demo.ui.queue_free()
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

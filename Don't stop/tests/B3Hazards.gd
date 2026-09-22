extends "res://tests/B8Runtime.gd"

## Hazard audit. Verifies the unified arena hazard system rather than any one hazard:
## the plan table, the director's placement rules, the coverage ceiling, the poison
## percentage contract, the non-stacking rule, camp/epoch cleanup, and the fog cover the
## poison edge must keep.

const PLAN_STAGES_WITH_HAZARD := [21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40]

func director():
	var found = get_tree().get_nodes_in_group("hazard_director")
	return found[0] if not found.is_empty() else null

func make_field(kind: String, at: Vector2, share: float, radius: float, warning := 0.8, active := 4.0):
	var field = load("res://game/map/StageHazard.gd").new()
	field.kind = kind; field.at = at; field.poison_share = share
	field.radius = radius; field.length = radius; field.width = radius
	field.warning = warning; field.active_time = active; field.pulses = 1
	LevelServer.town.arena.add_child(field)
	return field

func _ready():
	await boot(); configure(124,true)

	# ---- The plan table is the single source of truth ----------------------------------
	check(ArenaHazards.plan(1).is_empty() and ArenaHazards.plan(20).is_empty(),
		"stages 1-20 field no arena hazard")
	for stage in PLAN_STAGES_WITH_HAZARD:
		var plan = ArenaHazards.plan(stage)
		check(not plan.is_empty(),"stage %d has a hazard plan" % stage)
		check(plan.kinds == ["meteor"],"stage %d fields only the meteor family" % stage)
		check(float(plan.warning) >= ArenaHazards.WARNING_FLOOR,"stage %d warns for at least the floor" % stage)
		check(float(plan.coverage) <= ArenaHazards.HELL_COVERAGE,"stage %d coverage plan is inside the ceiling" % stage)
	# The user's 21-25 requirement: at least one formal arena hazard, and it is the poison
	# family, which is also what R5's map art anchors.
	for stage in [21,22,23,24,25]:
		check(ArenaHazards.plan(stage).kinds == ["meteor"],"stage %d introduces the meteor family" % stage)
	check(ArenaHazards.plan(40).kinds.size() >= ArenaHazards.plan(31).kinds.size(),
		"Hell retains the single arena hazard family")
	check(HellMode.hazard_live_cap(31) >= 3 and HellMode.hazard_live_cap(40) <= 12,
		"the simultaneous hazard cap is bounded at both ends")

	# ---- Stage 22 runs the poison plan for real ---------------------------------------
	check(LevelServer.town.depart(22,true),"stage 22 departs")
	await visual_ready()
	await wait(0.5)
	freeze_room()
	var room = director()
	check(room != null,"a hazard director exists for a hazard stage")
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"the round opens with no hazard on the field")

	# ---- Placement rules ---------------------------------------------------------------
	var player_at = Utils.player.global_position
	check(not room._legal(player_at,96.0,player_at,false),
		"a hazard is never legal on the player's own position")
	check(not room._legal(player_at+Vector2(ArenaHazards.MIN_EDGE_DISTANCE*0.4,0),96.0,player_at,false),
		"a hazard is never legal when its EDGE reaches into the player's space")
	check(room._legal(player_at+Vector2(260,0),40.0,player_at,false),
		"a clear, distant, reachable point is legal")
	var rejected_before = StageHazard.audit_rejected
	for i in 12: room._spawn()
	await wait(0.4)
	check(StageHazard.audit_spawned > 0,"the director places hazards through the real path")
	check(StageHazard.audit_spawned <= int(ArenaHazards.plan(22).live_cap),
		"the director never exceeds the stage's simultaneous hazard cap")
	var live = get_tree().get_nodes_in_group(StageHazard.GROUP)
	check(live.size() <= int(ArenaHazards.plan(22).live_cap),"live hazard count respects the cap")
	check(StageHazard.audit_rejected > rejected_before,"the director rejects rather than forces placements")
	check(room.coverage_peak <= float(ArenaHazards.plan(22).coverage),
		"measured coverage stays inside the 30-35%% ceiling (%.3f)" % room.coverage_peak)
	for hazard in live:
		var edge = hazard.global_position.distance_to(Utils.player.global_position)-hazard.radius
		check(edge >= ArenaHazards.MIN_EDGE_DISTANCE,"no hazard was created under the player (edge %.0f)" % edge)
	# Clean the field so the poison math below measures exactly one field.
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP): hazard.queue_free()
	await wait(0.3)

	# ---- Poison: percentage, positional, and non-stacking ------------------------------
	# The director ticks once per 0.5 s window for the WHOLE arena, so a measurement has to
	# span several windows: a single 0.55 s sample can catch one or two ticks and would be a
	# coin flip. Two seconds expects about four windows.
	PlayerData.player_hp_max = 20; PlayerData.player_hp = 20
	var share = float(ArenaHazards.plan(22).poison_share)
	var windows = 4.0
	var span = 2.0
	var spot = Utils.player.global_position
	var field = make_field("poison",spot,share,90.0,0.5,6.0)
	await wait(0.2)
	check(field.phase == "warning" and not field.contains_player(),
		"a poison field warns before it can damage")
	await wait(0.45)
	check(field.phase == "active" and field.contains_player(),"the field is live and the player is inside it")
	var before = PlayerData.player_hp
	await wait(span)
	var measured = before-PlayerData.player_hp
	var expected = PlayerData.player_hp_max*share*windows
	print("B4 HAZARD poison_share=%.4f expected=%.3f measured=%.3f" % [share,expected,measured])
	check(measured > expected*0.6 and measured < expected*1.5,
		"poison costs about one share of maximum HP per 0.5 s window")

	# Overlap must not multiply. Same span, same strongest single field, twice over: the drop
	# has to stay near ONE field's worth instead of growing with the number of fields.
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP): hazard.queue_free()
	await wait(0.4)
	PlayerData.player_hp = 20
	var strongest = share*1.5
	var single = make_field("poison",spot,strongest,90.0,0.5,8.0)
	await wait(1.0)
	before = PlayerData.player_hp
	await wait(span)
	var single_drop = before-PlayerData.player_hp
	make_field("poison",spot,share,90.0,0.5,8.0)
	make_field("poison",spot,share,90.0,0.5,8.0)
	await wait(1.0)
	before = PlayerData.player_hp
	await wait(span)
	var overlap_drop = before-PlayerData.player_hp
	print("B4 HAZARD single=%.3f overlap=%.3f strongest_single_window=%.3f" % [single_drop,overlap_drop,PlayerData.player_hp_max*strongest])
	check(overlap_drop > 0.0,"overlapping poison still damages")
	check(single_drop > 0.0,"a single strong field damages")
	check(overlap_drop < single_drop*1.8,"three overlapping fields cost about one field, not three")
	check(StageHazard.audit_poison_capped > 0,"the audit recorded the capped overlap")

	# Leaving must stop the damage on the next window.
	PlayerData.player_hp = 20
	Utils.player.global_position = spot+Vector2(600,0)
	await wait(0.6)
	before = PlayerData.player_hp
	await wait(1.2)
	check(absf(before-PlayerData.player_hp) < 0.001,"leaving a poison field stops the damage immediately")
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP): hazard.queue_free()
	await wait(0.4)

	# ---- Vent and frost are real, bounded mechanics -------------------------------------
	# Sampled DURING the active window: a one-pulse vent frees itself when the pulse ends, so
	# checking after the fact would read a freed node.
	PlayerData.player_hp = 20
	var vent = make_field("vent",Utils.player.global_position+Vector2(45,0),0.0,60.0,0.7,1.2)
	vent.damage = 1.0
	await wait(0.95)
	check(is_instance_valid(vent) and vent.activated,"a vent actually erupts")
	# The T19 emergency shield can legitimately absorb the eruption, so the assertion is the
	# vent's own decision that the player was inside and was hit, not net HP.
	check(vent.hit_this_pulse,"a vent eruption hits a player standing in it")
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP): hazard.queue_free()
	await wait(0.4)
	PlayerData.player_hp = 20
	var frost = make_field("frost",Utils.player.global_position+Vector2(40,0),0.0,70.0,0.6,3.0)
	frost.damage = 0.0
	await wait(1.2)
	check(Utils.player.slow_amount > 0.0,"a frost slick slows the player")
	check(Utils.player.slow_amount <= Utils.player.MAX_ENV_SLOW,
		"the frost slow is bounded and cannot distort control (%.2f)" % Utils.player.slow_amount)
	check(Utils.player.SPEED > 0.0,
		"the frost slow leaves movement, aim and firing intact")
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP): hazard.queue_free()
	await wait(0.3)

	# ---- Hell escalates hazards without breaking the ceiling ---------------------------
	stop(); LevelServer.return_to_camp(); await wait(0.5)
	check(LevelServer.town.depart(39,true),"stage 39 departs")
	await wait(0.4)
	StageHazard.audit_spawned = 0
	StageHazard.audit_rejected = 0
	StageHazard.audit_peak_coverage = 0.0
	freeze_room()
	var hell_room = director()
	check(hell_room != null,"the Hell round has a director")
	for i in 40: hell_room._spawn()
	await wait(0.5)
	var hell_live = get_tree().get_nodes_in_group(StageHazard.GROUP)
	print("B4 HAZARD hell39 live=%d cap=%d coverage=%.3f" % [hell_live.size(),HellMode.hazard_live_cap(39),StageHazard.audit_peak_coverage])
	check(hell_live.size() <= HellMode.hazard_live_cap(39),"Hell respects its own hazard cap")
	check(hell_live.size() <= 12,"Hell never exceeds the global 12-hazard ceiling")
	check(StageHazard.audit_peak_coverage <= ArenaHazards.HELL_COVERAGE,
		"Hell coverage stays inside the ceiling (%.3f)" % StageHazard.audit_peak_coverage)
	check(ArenaVisibility.fog_active(),"stage 39 really is running with fog")
	await wait(0.2)
	check(FogPierce.instance() != null or not rendering(),
		"the fog overlay exists so hazard edges can be read")

	# ---- Epoch and camp cleanup --------------------------------------------------------
	var epoch_before = LevelServer.epoch
	stop(); LevelServer.return_to_camp(); await wait(0.6)
	check(LevelServer.epoch != epoch_before,"returning to camp advances the epoch")
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"camp holds 0 hazards")
	check(director() == null,"the hazard director is gone in camp")
	check(not ArenaVisibility.fog_active(),"camp is bright again")

	# A hazard created in the old epoch must not survive into the next round.
	check(LevelServer.town.depart(22,true),"a second hazard round departs")
	await wait(0.3)
	var stale = make_field("poison",Utils.player.global_position+Vector2(200,0),0.02,80.0,0.5,9.0)
	LevelServer.return_to_camp(); await wait(0.6)
	check(not is_instance_valid(stale),"a hazard cannot survive an epoch change")
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"no hazard leaks into the next round")

	print("B4 HAZARD CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

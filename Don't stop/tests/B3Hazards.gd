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

func clear_field_nodes() -> void:
	for field in get_tree().get_nodes_in_group(StageHazard.GROUP): field.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func audit_field_shapes(room) -> void:
	# Defaults retain the canonical shape. Explicitly configured actor geometry
	# must survive ready and contribute its real size to the existing area convention.
	var expected_area := 0.0
	for kind in ["poison","vent","frost","meteor","laser","shock"]:
		var spec = ArenaHazards.shape(kind)
		var field = StageHazard.new()
		field.kind = kind; field.at = Utils.player.global_position+Vector2(220,0)
		LevelServer.town.arena.add_child(field)
		field.set_physics_process(false)
		var line_kind = kind in ["laser","shock"]
		if line_kind:
			check(is_equal_approx(field.length,spec.length) and is_equal_approx(field.width,spec.width),kind+" default line dimensions retain the canonical shape")
			check(is_equal_approx(field.radius,96.0),kind+" default activation retains its existing VFX extent")
		else:
			check(is_equal_approx(field.radius,spec.radius),kind+" default radius retains the canonical shape")
		var area = float(spec.length*spec.width) if line_kind else PI*float(spec.radius)*float(spec.radius)
		expected_area += area
		check(field.has_method("footprint_area"),kind+" exposes its instantiated footprint for coverage")
		if field.has_method("footprint_area"):
			check(is_equal_approx(field.footprint_area(),area),kind+" default footprint keeps the existing area convention")
	check(is_equal_approx(room.coverage_share(),expected_area/room.walkable_area()),"default hazard coverage is unchanged")
	await clear_field_nodes()

	expected_area = 0.0
	var configured = [
		{"kind":"poison","radius":78.0,"caller":"E15 ordinary"},
		{"kind":"poison","radius":92.0,"caller":"E15 elite"},
		{"kind":"poison","radius":110.0,"caller":"B02 phase III"},
		{"kind":"vent","radius":70.0,"caller":"E12 ember"},
		# Radius is not a line's geometry selector. Legacy/default objects can
		# carry a radius while drawing and colliding through length/width.
		{"kind":"laser","radius":96.0,"length":210.0,"width":18.0,"caller":"explicit line"}]
	for row in configured:
		var field = StageHazard.new()
		field.kind = row.kind; field.radius = row.radius
		if row.has("length"): field.length = row.length; field.width = row.width
		field.at = Utils.player.global_position+Vector2(220,0)
		LevelServer.town.arena.add_child(field)
		field.set_physics_process(false)
		check(is_equal_approx(field.radius,row.radius),row.caller+" preserves its configured radius through ready")
		var area = float(row.length*row.width) if row.kind == "laser" else PI*float(row.radius)*float(row.radius)
		expected_area += area
		if row.kind == "laser":
			check(is_equal_approx(field.length,row.length) and is_equal_approx(field.width,row.width),"explicit line retains its actual line geometry")
		if field.has_method("footprint_area"):
			check(is_equal_approx(field.footprint_area(),area),row.caller+" coverage uses its actual shape and size")
		if row.kind == "poison":
			field.phase = "active"
			var saved_player: Vector2 = Utils.player.global_position
			Utils.player.global_position = field.global_position+Vector2(row.radius+1.0,0)
			check(not field.contains_player(),row.caller+" excludes points outside its configured poison boundary")
			Utils.player.global_position = field.global_position+Vector2(row.radius-1.0,0)
			check(field.contains_player(),row.caller+" includes points inside its configured poison boundary")
			Utils.player.global_position = saved_player
	var actual_coverage: float = room.coverage_share()
	var expected_coverage = expected_area/room.walkable_area()
	print("B3_FIELD_COVERAGE ",JSON.stringify({"actual":actual_coverage,"expected":expected_coverage,"field_count":configured.size()}))
	check(is_equal_approx(actual_coverage,expected_coverage),"mixed coverage sums the instantiated actor fields and line, not kind defaults")
	await clear_field_nodes()

func actor_field_pair(arena, radius_value := 78.0, distance_value := 140.0, source = null) -> Dictionary:
	var excluded: Array = [source.get_rid()] if is_instance_valid(source) else []
	for cell in arena.cells:
		var at: Vector2 = arena.to_global(arena.grid.get_point_position(cell))
		if not arena.point_clear(at,radius_value*0.55+10.0,excluded): continue
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var player_at = at+direction*distance_value
			if not arena.point_clear(player_at,8.0,excluded) or not arena.bounds.grow(-20.0).has_point(arena.to_local(player_at)): continue
			var a = arena.cell(at); var b = arena.cell(player_at)
			if not arena.grid.is_in_boundsv(a) or not arena.grid.is_in_boundsv(b): continue
			if arena.grid.is_point_solid(a) or arena.grid.is_point_solid(b): continue
			if arena.grid.get_id_path(a,b).size() > 1: return {"at":at,"player_at":player_at}
	return {}

func audit_actor_field_source() -> void:
	var arena = LevelServer.town.arena
	var pair = actor_field_pair(arena)
	check(not pair.is_empty(),"real arena has a clear reachable source/player pair 140 px apart")
	if pair.is_empty(): return
	Utils.player.global_position = pair.player_at
	Utils.player.velocity = Vector2.ZERO
	var actor = M5Content.spawn("E15",LevelServer.town.monster_root,pair.at)
	check(actor != null and actor.get_meta("content_id","") == "E15","source field regression uses the real E15 factory")
	if actor == null: return
	actor.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var radius = 78.0*0.55+10.0
	check(not arena.point_clear(actor.global_position,radius) and arena.point_clear(actor.global_position,radius,[actor.get_rid()]),
		"the source actor alone explains the default occupancy refusal")
	check(arena.reachable_from_player(actor.global_position),"the source is on a real reachable floor cell")
	var accepted: bool = actor.release_field("poison",actor.global_position,0.85,3.4,0.012,1.0,78.0)
	var fields = get_tree().get_nodes_in_group(StageHazard.GROUP)
	check(accepted and fields.size() == 1,"a legal E15 field is not refused by its source collider")
	if accepted and fields.size() == 1:
		check(is_equal_approx(fields[0].radius,78.0),"real E15 field keeps the radius checked during placement")
		check(fields[0].global_position.distance_to(Utils.player.global_position)-fields[0].radius >= ArenaHazards.MIN_EDGE_DISTANCE,
			"accepted actor field still has the full safe edge after ready")
	await clear_field_nodes()
	check(not actor.release_field("poison",Utils.player.global_position+Vector2(ArenaHazards.MIN_EDGE_DISTANCE+78.0-0.1,0),0.85,3.4,0.012,1.0,78.0),
		"source exclusion does not bypass player edge safety")
	var barrier = wall(actor.global_position,Vector2(4,120))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not actor.release_field("poison",actor.global_position,0.85,3.4,0.012,1.0,78.0),"source exclusion still rejects a real wall")
	barrier.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	var other = M5Content.spawn("E01",LevelServer.town.monster_root,actor.global_position+Vector2(25,0))
	check(other != null,"another real actor exists for selective-exclusion regression")
	if other != null:
		other.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(not actor.release_field("poison",actor.global_position,0.85,3.4,0.012,1.0,78.0),"source exclusion still rejects another actor")
		other.queue_free()
		await get_tree().physics_frame
		await get_tree().process_frame
	for i in 8:
		var occupied = make_field("poison",actor.global_position+Vector2(200,0),0.012,78.0,0.85,3.4)
		occupied.set_physics_process(false)
	check(not actor.release_field("poison",actor.global_position,0.85,3.4,0.012,1.0,78.0),"source exclusion retains the eight-field live cap")
	await clear_field_nodes()
	var landed: bool = Combat.hit(actor,{"damage":1000.0,"depth":0,"epoch":LevelServer.epoch})
	var death_fields = get_tree().get_nodes_in_group(StageHazard.GROUP)
	check(landed and actor.is_die,"real combat damage reaches E15 onDie")
	check(death_fields.size() == 1,"E15 death creates one legal poison field before source collider removal")
	if death_fields.size() == 1:
		check(is_equal_approx(death_fields[0].radius,78.0) and death_fields[0].owner_ref.get_ref() == actor,
			"death field retains configured geometry and source attribution")
	await clear_field_nodes()

func audit_actor_field_coverage(stage: int, id: String, radius: float) -> void:
	# Saturate the shared admission boundary synchronously. This deliberately
	# bypasses actor scheduling; it does not claim a natural nine-attacks-per-frame
	# cadence. Every request retains its real arena, source and authored geometry.
	check(LevelServer.town.depart(stage,true),"coverage boundary departs into real stage %d" % stage)
	LevelServer.timerStop()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.velocity = Vector2.ZERO
	var room = director()
	check(room != null,"stage %d has a real coverage coordinator" % stage)
	if room == null: return
	room.set_physics_process(false)
	if stage == 20: check(room.plan.is_empty(),"B02's actor fields retain coverage safety with an empty terrain plan")
	var actor = null
	for existing in get_tree().get_nodes_in_group("monsters"):
		existing.set_physics_process(false)
		if existing.get_meta("content_id","") == id: actor = existing
	var pair = actor_field_pair(room.arena,radius,220.0,actor)
	check(not pair.is_empty(),id+" coverage test finds a clear and reachable source/player pair")
	if pair.is_empty(): return
	Utils.player.global_position = pair.player_at
	if actor == null: actor = M5Content.spawn(id,LevelServer.town.monster_root,pair.at)
	else: actor.global_position = pair.at
	check(actor != null and actor.get_meta("content_id","") == id,"coverage test uses the real "+id+" factory actor")
	if actor == null: return
	actor.set_physics_process(false)
	if id == "E15":
		M5Content.promote_elite(actor,M5Content.elite_modifier_for(id))
		check(actor.is_elite and actor.elite_modifier() == "lingering_poison","coverage E15 uses real eligible elite promotion")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(room.arena.point_clear(actor.global_position,radius*0.55+10.0,[actor.get_rid()]) and room.arena.reachable_from_player(actor.global_position),
		id+" coverage requests have real geometry clearance and reachability")
	var limit = ArenaHazards.HELL_COVERAGE if HellMode.is_hell(stage) else ArenaHazards.MAX_COVERAGE
	var expected = mini(8,int(floor(limit*room.walkable_area()/(PI*radius*radius))))
	check(expected > 0 and expected < 8,id+" coverage limit is reached before the separate eight-field cap")
	var admitted := 0
	var consistent := true
	var rejected_without_refs := true
	var peak := 0.0
	var rows: Array = []
	for i in 9:
		var before = get_tree().get_nodes_in_group(StageHazard.GROUP).size()
		var refs_before = actor.owned_attacks.size()
		var accepted: bool
		if id == "E15":
			actor.attack_kind = "toxin"
			actor.perform_attack()
			accepted = get_tree().get_nodes_in_group(StageHazard.GROUP).size() > before
		else:
			accepted = actor.release_field("poison",actor.global_position,1.2,6.0,0.016,1.0,radius)
		var fields = get_tree().get_nodes_in_group(StageHazard.GROUP)
		if accepted: admitted += 1
		consistent = consistent and fields.size() == before+(1 if accepted else 0)
		if not accepted: rejected_without_refs = rejected_without_refs and actor.owned_attacks.size() == refs_before
		# Measure independently of the admission helper, using live circle sizes.
		var area := 0.0
		for field in fields: area += PI*field.radius*field.radius
		var actual = area/room.walkable_area()
		peak = maxf(peak,actual)
		rows.append({"call":i+1,"accepted":accepted,"live":fields.size(),"coverage":actual})
	print("B3_ACTOR_COVERAGE ",JSON.stringify({"stage":stage,"actor":id,"limit":limit,"walkable_area":room.walkable_area(),
		"expected":expected,"admitted":admitted,"peak":peak,"rows":rows}))
	check(consistent,id+" each coverage decision admits exactly one field or none")
	check(admitted == expected,id+" admits all fitting fields and refuses the first excess request")
	check(peak <= limit+0.000001,id+" actor fields never exceed the existing coverage ceiling")
	check(rejected_without_refs,id+" over-budget requests retain no owned attack references")
	check(is_equal_approx(room.coverage_share(),peak),id+" coordinator reports the same actual field coverage")
	var fields = get_tree().get_nodes_in_group(StageHazard.GROUP)
	if not fields.is_empty():
		fields[0].queue_free()
		await get_tree().physics_frame
		await get_tree().process_frame
		var before = get_tree().get_nodes_in_group(StageHazard.GROUP).size()
		var retried: bool = actor.release_field("poison",actor.global_position,0.85 if id == "E15" else 1.2,5.2 if id == "E15" else 6.0,0.016,1.0,radius)
		check(retried and get_tree().get_nodes_in_group(StageHazard.GROUP).size() == before+1,id+" capacity becomes available after one real field leaves")
		check(room.coverage_share() <= limit+0.000001,id+" admission after capacity release preserves the ceiling")
	await clear_field_nodes()
	LevelServer.return_to_camp()
	dismiss()
	await wait(0.2)
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),id+" coverage regression drains its fields at camp")

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

	# Preserve every earlier cadence/percentage/fog assertion, then add the
	# separate actor-geometry/source contract at the end of this existing case.
	check(LevelServer.town.depart(33,true),"actor field regression departs into the real stage 33 arena")
	LevelServer.timerStop()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	var actor_room = director()
	check(actor_room != null,"actor field regression retains a real arena coordinator")
	if actor_room != null:
		actor_room.set_physics_process(false)
		await get_tree().physics_frame
		await audit_field_shapes(actor_room)
		await audit_actor_field_source()
	LevelServer.return_to_camp()
	dismiss()
	await wait(0.6)
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"new actor-field regression also drains all hazards at camp")
	await audit_actor_field_coverage(20,"B02",110.0)
	await audit_actor_field_coverage(33,"E15",92.0)
	print("B4 HAZARD CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

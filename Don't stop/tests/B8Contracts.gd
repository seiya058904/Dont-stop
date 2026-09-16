extends "res://tests/B8Probe.gd"

## B8 probe contracts. This scene exists so the expensive batch is never the first thing that
## runs a new instrument: every number the batch will quote is first proved here, on real game
## code paths, in seconds.
##
## Three things are asserted, and the second one is the one that matters most:
##   1. the attribution channel reports the mechanism the call site actually used, for every
##      player-damage path in the game - and a hit that was ABSORBED is not counted at all;
##   2. attaching the telemetry changes nothing about the damage maths: Hero.damage_taken and
##      Hero.incoming_hit report byte-identical raw/applied values for every hit, and the
##      values themselves still satisfy the documented rules (contact multiplier, fractional
##      barrage pellets with a zero floor, percentage read from MAX HP);
##   3. the escape probe answers the question it claims to answer - it finds an escape in an
##      open arena, reports none when the arena is genuinely denied, ignores poison (which
##      prices standing still but cannot deny movement) and can tell a footprint the fog gate
##      would not have released from one that was legally allowed to open.
##
## Fast by construction: no round is played, no long survival loop, no boss.

var observed: Array = []
var paired: Array = []
var dummy: Node2D

func _observe(raw: float, applied: float, tag: String, attacker) -> void:
	observed.append({"tag":tag,"applied":applied,"raw":raw,
		"attacker":str(attacker.get_meta("content_id","")) if is_instance_valid(attacker) else ""})

func _pair(raw: float, applied: float, boss: bool) -> void:
	paired.append({"raw":raw,"applied":applied,"boss":boss})

func reset_watch() -> void:
	observed = []; paired = []

func tags() -> Array:
	var out := []
	for entry in observed: out.append(entry.tag)
	return out

## Safe accessor: a failed expectation must report a wrong number, not crash the scene and hide
## every check after it.
func first_applied() -> float:
	return float(observed[0].applied) if observed.size() > 0 else -1.0

func first_raw() -> float:
	return float(observed[0].raw) if observed.size() > 0 else -1.0

func paired_applied() -> float:
	return float(paired[0].applied) if paired.size() > 0 else -2.0

func paired_raw() -> float:
	return float(paired[0].raw) if paired.size() > 0 else -2.0

func live_state() -> void:
	LevelServer.state = "COMBAT"

func drop_zone(mode: String, at: Vector2, radius: float, warning: float, damage_value: float, owner, style := "", duration := 0.25) -> Node2D:
	var zone = load("res://game/monster/HostileZone.gd").new()
	zone.mode = mode; zone.radius = radius; zone.length = radius
	zone.warning = warning; zone.duration = duration; zone.damage = damage_value
	zone.world_point = at; zone.style = style
	zone.owner_ref = weakref(owner) if is_instance_valid(owner) else null
	get_tree().current_scene.add_child(zone)
	return zone

## A real actor used only as the owner of a zone. HostileZone.step() reads `owner.is_die` and
## frees itself when the owner is gone, so the owner has to be a real monster rather than a bare
## Node2D - and it is frozen so it cannot fire anything of its own and pollute the ledger.
func frozen_owner(id: String, at: Vector2) -> Node2D:
	var parent = spawn_parent()
	if parent == null: return null
	var actor = M5Content.spawn(id,parent,at)
	if is_instance_valid(actor):
		actor.set_physics_process(false)
		actor.set_meta("content_id",id)
	return actor

## M5Content.spawn() places the actor with parent.to_local(), so the parent must be a Node2D.
## get_tree().current_scene is this test's own plain Node, and no arena exists until a round
## departs, so the town root - the same kind of parent Town.gd uses in production - is the right
## one here.
func spawn_parent() -> Node2D:
	if is_instance_valid(LevelServer.town) and LevelServer.town is Node2D: return LevelServer.town
	if is_instance_valid(Utils.player) and Utils.player.get_parent() is Node2D: return Utils.player.get_parent()
	return null

## A set of active damaging footprints centred on the player: geometrically, and with clear line
## of sight, no reachable point inside them. Used only to prove the probe can say "denied" at
## all. The duration is long enough that they outlive the samples they exist to be measured by.
func deny_arena(at: Vector2) -> Array:
	var made := []
	for i in 4:
		made.append(drop_zone("circle",at,420.0,0.0,1.0,null,"",6.0))
	await wait(0.4)
	return made

func clear_transients() -> void:
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for node in get_tree().get_nodes_in_group("monsters"): node.queue_free()
	await wait(0.3)

## Zones and hazards free themselves when their pulse ends, so a teardown must never assume the
## node it created is still alive - an unguarded queue_free() here aborts the scene and hides
## every check after it.
func retire(nodes) -> void:
	if nodes is Array:
		for node in nodes:
			if is_instance_valid(node): node.queue_free()
	elif is_instance_valid(nodes):
		nodes.queue_free()

func _ready():
	await boot()
	configure(117,false)
	Demo.talents = {}
	Demo.refresh()
	Utils.player.damage_taken.connect(_observe)
	Utils.player.incoming_hit.connect(_pair)
	dummy = Node2D.new()
	get_tree().current_scene.add_child(dummy)

	# ---- 1. behaviour preservation: the new signal duplicates, it does not alter ------------
	# onHit() is a no-op outside COMBAT, so the state has to be COMBAT for this section. No
	# round is running: the round timer is only started by LevelServer.roundStart().
	live_state()
	PlayerData.player_hp_max = 100; PlayerData.player_hp = 100
	reset_watch()
	Utils.player.onHit(4.0,dummy)
	check(observed.size() == 1 and paired.size() == 1,"a real hit is reported on both channels")
	check(is_equal_approx(first_applied(),paired_applied()) and is_equal_approx(first_raw(),paired_raw()),
		"damage_taken and incoming_hit agree on raw and applied (%.4f/%.4f vs %.4f/%.4f)" % [first_raw(),first_applied(),paired_raw(),paired_applied()])
	check(is_equal_approx(first_applied(),4.0*DemoConfig.NORMAL_INCOMING),
		"a non-boss hit still takes the normal incoming multiplier (%.4f)" % first_applied())
	check(is_equal_approx(float(PlayerData.player_hp),100.0-first_applied()),"HP moved by exactly the reported amount")
	PlayerData.player_hp = 100
	reset_watch()
	Utils.player.onHit(0.4,dummy,0.0)
	check(observed.size() == 1 and is_equal_approx(first_applied(),0.4*DemoConfig.NORMAL_INCOMING),
		"a fractional barrage pellet still bypasses the one-point floor (%.4f)" % first_applied())
	PlayerData.player_hp = 100
	reset_watch()
	Utils.player.onHit(2.0,dummy,3.0)
	check(observed.size() == 1 and is_equal_approx(first_applied(),3.0*DemoConfig.NORMAL_INCOMING),
		"minimum_pressure still raises a weak hit (%.4f)" % first_applied())
	PlayerData.player_hp = 100
	reset_watch()
	Utils.player.on_percentage_hit(0.3)
	check(observed.size() == 1 and is_equal_approx(first_applied(),30.0),
		"a percentage payload still reads from MAX HP and skips the incoming multiplier (%.4f)" % first_applied())
	check(observed.size() == 1 and observed[0].tag == "percentage","the direct percentage path still reports its own tag")
	check(is_equal_approx(float(PlayerData.player_hp),70.0),"MAX HP pool moved by exactly 30")
	# An absorbed hit is not damage and must never enter the ledger: T19 spends a shield and
	# returns before the emit, so counting it would overstate incoming pressure.
	Demo.talents = {"T19":1}; Demo.refresh()
	check(Demo.cooldown("T19") <= 0.0,"T19 shield is ready")
	PlayerData.player_hp = 100
	reset_watch()
	Utils.player.onHit(12.0,dummy)
	check(PlayerData.player_hp == 100,"T19 absorbs the hit")
	check(observed.is_empty(),"an absorbed hit is not reported as damage taken")
	Demo.talents = {}; Demo.refresh()
	# A dead player and a paused tree do not take damage, so they must not report any either.
	PlayerData.player_hp = 100
	reset_watch()
	Utils.player.is_dead = true
	Utils.player.onHit(12.0,dummy)
	Utils.player.is_dead = false
	check(observed.is_empty() and PlayerData.player_hp == 100,"a dead player takes and reports nothing")
	reset_watch()
	Demo.push_pause(self)
	Utils.player.onHit(12.0,dummy)
	Demo.pop_pause(self)
	check(observed.is_empty() and PlayerData.player_hp == 100,"a paused tree takes and reports nothing")

	# ---- 2. attribution: every real mechanism reports its own tag --------------------------
	live_state()
	var origin = Utils.player.global_position
	PlayerData.player_hp_max = 200; PlayerData.player_hp = 200

	reset_watch()
	var zone = drop_zone("artillery",origin+Vector2(4,0),46.0,0.2,1.0,null)
	await wait(0.7)
	check("artillery" in tags(),"a real HostileZone artillery footprint reports 'artillery' (saw %s)" % str(tags()))
	retire(zone); await wait(0.2)

	reset_watch()
	# A real E10 is the owner, so the zone's own `owner.is_die` check is satisfied by the same
	# kind of node the game actually passes. It is frozen: this contract is about attribution,
	# not about letting a second attacker add events.
	var beam_owner = frozen_owner("E10",origin+Vector2(300,0))
	check(is_instance_valid(beam_owner),"a real E10 exists to own the beam zone")
	var beam = drop_zone("beam",origin+Vector2(4,0),46.0,0.2,1.0,beam_owner,"",1.2)
	await wait(0.7)
	check("beam" in tags(),"a real beam zone reports 'beam' (saw %s)" % str(tags()))
	check(observed.size() > 0 and observed[0].attacker == "E10","the beam's attacker is carried through")
	check(observed.size() > 0 and category_for("beam",beam_owner) == "beam_or_hostile_zone","the beam classifies as a hostile-zone attack")
	retire(beam); retire(beam_owner); await wait(0.2)

	reset_watch()
	var shot = load("res://game/monster/EnemyShot.gd").new()
	shot.position = Utils.player.global_position+Vector2(-44,0)
	shot.velocity = Vector2(120,0); shot.damage = 1.0; shot.style = "projectile"; shot.control = 0.0
	get_tree().current_scene.add_child(shot)
	await wait(0.9)
	check("shot:projectile" in tags(),"a real enemy projectile reports its family (saw %s)" % str(tags()))
	await wait(0.3)

	reset_watch()
	var rootshot = load("res://game/monster/EnemyShot.gd").new()
	rootshot.position = Utils.player.global_position+Vector2(-44,0)
	rootshot.velocity = Vector2(120,0); rootshot.damage = 1.0; rootshot.style = "root"; rootshot.control = 0.45
	get_tree().current_scene.add_child(rootshot)
	await wait(0.9)
	check("control_shot:root" in tags(),"a real control projectile is not filed as plain damage (saw %s)" % str(tags()))
	await wait(0.3)

	reset_watch()
	var barrage_pellet = load("res://game/monster/EnemyShot.gd").new()
	barrage_pellet.position = Utils.player.global_position+Vector2(-44,0)
	barrage_pellet.velocity = Vector2(120,0); barrage_pellet.damage = 1.0
	barrage_pellet.style = "artillery"; barrage_pellet.control = 0.0
	get_tree().current_scene.add_child(barrage_pellet)
	await wait(0.9)
	check("shot:artillery" in tags(),"a barrage pellet keeps its attack family (saw %s)" % str(tags()))
	await wait(0.3)

	reset_watch()
	var hazard = load("res://game/map/StageHazard.gd").new()
	hazard.kind = "vent"; hazard.at = origin+Vector2(4,0); hazard.radius = 46.0
	hazard.warning = 0.2; hazard.active_time = 1.2; hazard.pulses = 1; hazard.damage = 1.0
	get_tree().current_scene.add_child(hazard)
	await wait(0.9)
	check("hazard_vent" in tags(),"a real arena hazard reports its own kind (saw %s)" % str(tags()))
	retire(hazard); await wait(0.2)

	# Contact, through the production path: a real E02 walking into the player.
	reset_watch()
	check(spawn_parent() != null,"a Node2D spawn parent exists for the spawn contracts")
	var runner = M5Content.spawn("E02",spawn_parent(),Utils.player.global_position+Vector2(26,0))
	check(is_instance_valid(runner),"an E02 spawns for the contact contract")
	if is_instance_valid(runner):
		await wait(1.4)
		check("contact" in tags(),"a real body contact reports 'contact' (saw %s)" % str(tags()))
		# Elite promotion is a property of the ACTOR, so the enrichment has to come from the
		# attacker rather than from a second tag at the call site.
		M5Content.promote_elite(runner,"pack")
		reset_watch()
		await wait(1.4)
		var elite_seen := false
		for tag in tags():
			if category_for(tag,runner) == "elite_contact": elite_seen = true
		check(elite_seen,"an elite contact classifies as elite_contact (saw %s)" % str(tags()))
		retire(runner)
	await clear_transients()

	# ---- 3. the escape probe answers the question it claims to -----------------------------
	reset_watch()
	live_state()
	var open = escape_report()
	check(int(open.safe_now) > 0 and int(open.safe_timed) > 0,
		"an empty arena offers an escape (%d safe of %d reachable)" % [int(open.safe_now),int(open.reachable)])
	check(int(open.safe_fair) > 0,"an empty arena offers an escape under the fair verdict too")

	var ring = await deny_arena(Utils.player.global_position)
	var denied = escape_report()
	check(int(denied.safe_now) == 0,"a full ring of active footprints denies the arena (%d safe of %d)" % [int(denied.safe_now),int(denied.reachable)])
	check(int(denied.safe_fair) == 0,"the fair verdict agrees while the fog gate is off")
	check(denied.modes.size() >= 1,"the probe names what denied the arena (%s)" % str(denied.modes))
	retire(ring)
	await wait(0.4)
	check(int(escape_report().safe_now) > 0,"freeing the ring reopens an escape")

	# Poison cannot deny movement: it stops damaging the tick after the player leaves it.
	var poison = load("res://game/map/StageHazard.gd").new()
	poison.kind = "poison"; poison.at = Utils.player.global_position; poison.radius = 300.0
	poison.warning = 0.1; poison.active_time = 4.0; poison.pulses = 1; poison.poison_share = 0.02
	get_tree().current_scene.add_child(poison)
	await wait(0.5)
	var poisoned = escape_report()
	check(int(poisoned.safe_now) > 0,"poison covering the whole arena does not count as denial")
	retire(poison); await wait(0.3)

	# The fog gate distinction: outside Hell a footprint blocks the moment it is live, so the
	# strict and fair verdicts must be identical - that is what guarantees B8's Normal numbers
	# are not being softened by the Hell-only rule.
	check(not ArenaVisibility.fog_active(),"Normal mode runs with the fog gate off")
	check(is_equal_approx(ZONE_FAIR_VISIBLE,StageHazard.FAIR_VISIBLE),
		"the probe's copied warning floor still matches the game's (%.2f vs %.2f)" % [ZONE_FAIR_VISIBLE,StageHazard.FAIR_VISIBLE])
	var normal_zone = drop_zone("artillery",Utils.player.global_position+Vector2(4,0),46.0,0.05,1.0,null,"",2.0)
	await wait(0.5)
	var strict_len := int(escape_report().modes.size())
	var fair_len := int(escape_report().fair_modes.size())
	check(strict_len > 0 and strict_len == fair_len,"outside Hell the strict and fair verdicts agree (%d vs %d)" % [strict_len,fair_len])
	retire(normal_zone)
	ArenaVisibility.apply_stage(31)
	check(ArenaVisibility.fog_active(),"Hell mode raises the fog gate")
	var gated = drop_zone("artillery",Utils.player.global_position+Vector2(4,0),46.0,0.05,1.0,null,"",2.0)
	check(gated.fair_gate,"a damaging zone arms the fog gate in Hell")
	await wait(0.5)
	var gated_report = escape_report()
	check(int(gated_report.get("safe_fair",-1)) > 0,
		"a footprint the fog gate has not released is not allowed to deny (%d fair escapes)" % int(gated_report.get("safe_fair",-1)))
	ArenaVisibility.restore(true)
	ArenaVisibility.reset()
	check(not ArenaVisibility.fog_active(),"the fog gate is released again")
	retire(gated)
	await clear_transients()
	LevelServer.state = "CAMP"

	Utils.player.damage_taken.disconnect(_observe)
	Utils.player.incoming_hit.disconnect(_pair)
	print("B8 CONTRACTS CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

extends "res://tests/M8Runtime.gd"

## B11.2 enemy-projectile collision contract - RUNTIME regression.
##
## WHY THIS EXISTS. Every `EnemyShot` used to undo, one body at a time, the layer its own mask had
## just asked for:
##
##     collision_mask = 2147483649                 # layer 1 (walls) + layer 32 (map statics)
##     add_collision_exception_with(Utils.player)
##     for actor in get_tree().get_nodes_in_group("monsters"): add_collision_exception_with(actor)
##
## Layer 1 is not "walls". It is the layer the HERO (25 = 1+8+16) and every MONSTER (3 = 1+2)
## share, and it is exactly why the exceptions were needed. Measured on the B11.2 worst-load
## profile that cost 83 physics-server pair insertions per shot - 26,846 of them in a 45 s run -
## all of it arriving in the burst the moment a barrage is fired, and all of it removing an
## exception that only existed because of the extra mask bit.
##
## The mask is now layer 32 alone. This file is the RUNTIME half of the proof that the saving did
## not change one thing about behaviour - a static layer audit is an argument, not evidence, and it
## is deliberately not treated as sufficient here.
##
## WHAT IS PINNED, AND WITH WHAT:
##
##   A.  the invariant the change rests on, over the LIVE scene: every body the PLAYER's own mask
##       collides with also carries the shot's mask, so "cannot be walked through" implies "cannot
##       be shot through". Covers BOTH body families - `StaticBody2D` and the `TileSet` physics
##       layers behind every TileMap, which a StaticBody2D-only audit would have missed entirely.
##   A2. the same invariant over `SnowWorld.tscn`, instantiated DETACHED: the second authored map,
##       whose collision lives in tilemap layers rather than in static bodies.
##   B.  the shipped mask really is wall-only (layer 1 absent, so no exception can be needed).
##   C.  a control shot with nothing in its way survives the WHOLE corridor later sections use, so
##       D/E/H and G cannot pass by accident.
##   D.  the projectile passes THROUGH bodies on the monster layer and on the hero's own layer -
##       the two exclusions this round removed the need for.
##   H.  it also passes through a REAL spawned monster body, and that monster takes no damage.
##   E.  it still STOPS on geometry authored as layer 32 and as layer 1+32, on the near face.
##   E2. it stops on the LIVE arena's own border wall - real shipped geometry, not a stand-in.
##   K.  the ONE behaviour difference the change makes, measured instead of argued. The old build's
##       mask included layer 1 and then excluded the hero and every monster ALIVE AT SPAWN TIME; a
##       monster that spawned later was never excluded, so the old mask did stop shots on it and the
##       old behaviour depended on spawn order. K reconstructs that configuration on the shipped node
##       type and shows the same monster stopping one shot and not the other.
##
## COMPANION CHANGE, and the reason section A is an assertion rather than a comment. On its first
## run A FAILED: `MapNpc.tscn` and `RewardNpc.tscn` place their solid body on layer 1 ALONE (the
## implicit default when a `StaticBody2D` sets no layer), so the old mask stopped enemy shots on an
## NPC and the new one would have flown straight through. Both scenes now publish 2147483649 on
## that body - the exact value the town's building slabs already use - which restores the shipped
## behaviour and makes the invariant true everywhere: solid to the player implies solid to shots.
## Without this line the mask change would have been a real, if quiet, gameplay difference.
##   E3. every authored region obstacle table (R2..R8) blocks a shot, at the exact layer value the
##       arena itself publishes, so "Town / Snow / Hell block the same way" is asserted per region
##       rather than assumed from one sample.
##   G.  it still REALLY HITS the player: the product's own hit counter rises AND health is lost,
##       and the projectile is consumed.
##   F.  a REAL sentinel's own projectile carries the same mask, and the round's counter proves no
##       per-monster exception was added on the way.
##   J.  lifecycle is unchanged: an epoch change, the owner's death, and the 3.2 s lifetime each
##       still retire a live projectile.
##
## The projectile is the shipped `game/monster/EnemyShot.gd` on the shipped node type; only its
## start point and velocity are set, which is the minimum needed to make the geometry
## deterministic. J bumps `LevelServer.epoch`, so it runs LAST.

const WALL_LAYER := 2147483648
const BUILDING_LAYER := 2147483649
const MONSTER_LAYER := 3
const HERO_LAYER := 25
const SHOT_MASK := 2147483648
## The hero's own collision mask, read from Hero.tscn. Anything it collides with is geometry the
## player cannot walk through, and therefore geometry a shot must not fly through either.
const PLAYER_MASK := 2147483649
## A shot's own CollisionShape2D radius, so "stopped before the wall" can be stated exactly.
const SHOT_RADIUS := 3.0
const SPEED := 300.0
## Every authored region the combat arena can present. `M5Content.WALLS` is the arena's own table.
const REGIONS := ["R2","R3","R4","R5","R6","R7","R8"]
## The corridor the control shot proves clear, in world px from `origin`.
const CORRIDOR := 125.0

var bodies: Array = []
var live_arena: Node2D = null

## Clear every actor this test can leave behind, including the projectiles D/E/F/G/J fire -
## `M3Weapons.clean()` covers only monsters + combat_transient, and a stray shot would both
## interfere with the next section's corridor and inflate F's "fresh" diff.
func clean_actors() -> void:
	for group in ["monsters","hostile_zone","enemy_projectiles"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): node.queue_free()
	await wait(0.15)

func slab(pos: Vector2, size: Vector2, layer: int):
	var body = StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	body.position = pos
	bodies.append(body)
	return body

## The shipped projectile, positioned and aimed. Nothing else is configured: the mask, the group,
## the epoch and the collision shape all come from the product's own `_ready`.
func make_shot(at: Vector2) -> CharacterBody2D:
	var shot := CharacterBody2D.new()
	shot.set_script(load("res://game/monster/EnemyShot.gd"))
	add_child(shot)
	shot.global_position = at
	shot.velocity = Vector2(SPEED,0.0)
	shot.damage = 0.0
	shot.style = "projectile"
	return shot

## Fly for `seconds` and report where it got to. `alive` false means something stopped it, and
## the loop leaves early when it dies so a section never waits out a projectile that already
## resolved.
func fly(shot, seconds: float) -> Dictionary:
	var farthest: float = shot.global_position.x
	var frames := int(seconds*60.0)
	for i in frames:
		if not is_instance_valid(shot): break
		if shot.global_position.x > farthest: farthest = shot.global_position.x
		await wait(1.0/60.0)
	return {"alive":is_instance_valid(shot),"farthest":farthest}

## The hero is parked clear of every corridor that is not about testing a landing, so a section can
## never pass because of an accidental hit (and so the hero is never the reason a shot died).
func park_player(point: Vector2) -> void:
	if is_instance_valid(Utils.player): Utils.player.global_position = point

func walk(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children(): stack.append(child)
	return out

## Every `StaticBody2D` reachable from `root`, and every `TileSet` physics layer reachable from it.
## Both matter: the arena and the town slabs are static bodies, but both authored maps put their
## real collision in tilemap layers, and a body-only audit would silently skip them.
func blocking_surfaces(root: Node, nodes: Array) -> Array:
	var out: Array = []
	for node in nodes:
		if node is StaticBody2D:
			var static_layer: int = int((node as StaticBody2D).collision_layer)
			if static_layer != 0: out.append(["StaticBody2D %s" % node.name,static_layer])
		var raw: Variant = node.get("tile_set")
		if raw == null: continue
		var tiles: TileSet = raw as TileSet
		if tiles == null: continue
		var count: int = tiles.get_physics_layers_count()
		for i in count:
			var layer: int = int(tiles.get_physics_layer_collision_layer(i))
			if layer != 0: out.append(["TileSet %s/%d" % [node.name,i],layer])
	return out

## Run the invariant over a set of surfaces and return the offenders in the shot's terms.
func audit(surfaces: Array) -> Dictionary:
	var blocking := 0
	var offenders: Array = []
	for row in surfaces:
		var layer: int = int(row[1])
		if (layer & PLAYER_MASK) != 0:
			blocking += 1
			if (layer & SHOT_MASK) == 0: offenders.append("%s(%d)" % [row[0],layer])
	return {"blocking":blocking,"offenders":offenders}

func _ready():
	B11Probe.enabled = true
	await boot()
	await dismiss()
	await wait(0.3)
	var town = LevelServer.town
	LevelServer.state = "COMBAT"
	stop()
	# A REAL arena, built by the product's own region builder - the same `Town.prepare_region` call
	# `Town.gd` makes when a stage departs. The corridor sections need open ground with nothing
	# under it: a shot fired across the camp is stopped by the TileMap's own physics layer well
	# before the 125 px these sections need, which is correct behaviour but a useless ruler.
	# R7 because its authored obstacles leave a long clear lane at the height used below.
	town.prepare_region("R7")
	await wait(0.2)
	live_arena = town.arena as Node2D
	check(is_instance_valid(live_arena),"the product's own region builder produced a live arena")
	var origin: Vector2 = town.global_position + Vector2(-170.0,120.0)
	var park: Vector2 = town.global_position + Vector2(-620.0,-620.0)
	if is_instance_valid(live_arena):
		origin = live_arena.to_global(Vector2(-170.0,60.0))
		park = live_arena.to_global(Vector2(-390.0,-290.0))
	park_player(park)
	await wait(0.2)

	# ---- A. the invariant the change rests on, over the LIVE scene -----------------------------
	# Both body families, so the two authored maps' tilemap collision is covered and not just the
	# bodies the arena happens to create.
	var live_nodes := walk(get_tree().current_scene)
	var live_surfaces := blocking_surfaces(get_tree().current_scene,live_nodes)
	var live_audit := audit(live_surfaces)
	var live_statics := 0
	var live_tiles := 0
	for row in live_surfaces:
		if String(row[0]).begins_with("StaticBody2D"): live_statics += 1
		else: live_tiles += 1
	check(live_audit.blocking > 0,
		"the live scene really has surfaces the player collides with (%d of %d: %d static, %d tile)"
		% [live_audit.blocking,live_surfaces.size(),live_statics,live_tiles])
	check(live_tiles > 0,
		"...and the audit reaches the TileSet physics layers, not only the static bodies")
	check(live_audit.offenders.is_empty(),
		"every surface the player's mask collides with also carries the shot's wall layer "
		+ "(offenders: %s)"
		% [", ".join(live_audit.offenders) if not live_audit.offenders.is_empty() else "none"])

	# ---- A3. the companion scene change, asserted by name --------------------------------------
	# Section A already fails if any solid body lacks the wall bit, but the NPC bodies are the ones
	# that actually DID lack it, so they get an explicit assertion: a future edit that drops the
	# layer again re-breaks the old semantics silently otherwise.
	var npc_bodies := 0
	for node in live_nodes:
		if not (node is StaticBody2D): continue
		var body := node as StaticBody2D
		var holder = body.get_parent()
		if holder == null or holder.get_script() == null: continue
		var script_path: String = (holder.get_script() as Script).resource_path
		if not script_path.contains("/npc/"): continue
		npc_bodies += 1
		check((int(body.collision_layer) & SHOT_MASK) != 0,
			"the solid body of %s carries the wall bit, so a shot still stops on it (layer %d)"
			% [holder.name,int(body.collision_layer)])
	check(npc_bodies > 0,"the camp's solid NPC bodies were found for the blocking check (%d)" % npc_bodies)

	# ---- A2. the same invariant over the second authored map, instantiated DETACHED ------------
	# SnowWorld is loaded but never added to the tree: `collision_layer` is a plain property, so the
	# audit needs no running world, and nothing from another map can leak into this test's scene.
	var snow_path := "res://game/map/SnowWorld/SnowWorld.tscn"
	var snow_audit := {"blocking":0,"offenders":[]}
	var snow_total := 0
	if ResourceLoader.exists(snow_path):
		var snow: Node = load(snow_path).instantiate()
		var snow_surfaces := blocking_surfaces(snow,walk(snow))
		snow_total = snow_surfaces.size()
		snow_audit = audit(snow_surfaces)
		snow.free()
	check(snow_total > 0,
		"SnowWorld.tscn publishes blocking surfaces even without being in the tree (%d found)" % snow_total)
	check(snow_audit.blocking > 0,
		"...and they are surfaces the player collides with (%d)" % snow_audit.blocking)
	check(snow_audit.offenders.is_empty(),
		"SnowWorld blocks shots with exactly the same layers as Town (offenders: %s)"
		% [", ".join(snow_audit.offenders) if not snow_audit.offenders.is_empty() else "none"])

	# ---- B. the shipped mask really is wall-only -----------------------------------------------
	var probe := make_shot(origin)
	check(probe.collision_mask == SHOT_MASK,
		"a fresh projectile masks the wall layer alone (%d)" % probe.collision_mask)
	check(probe.collision_layer == 0,"...and publishes itself on no layer, as before")
	check((probe.collision_mask & 1) == 0,
		"layer 1 is NOT in the mask, which is what removes the per-monster exceptions")
	probe.queue_free()
	await wait(0.1)

	# ---- C. control: the WHOLE corridor used below is clear ------------------------------------
	var control = make_shot(origin)
	var c: Dictionary = await fly(control,0.60)
	check(c.alive and c.farthest > origin.x+CORRIDOR-5.0,
		"control: an unobstructed projectile travels the whole corridor (+%.0f px of %.0f)"
		% [c.farthest-origin.x,CORRIDOR])
	if c.alive: control.queue_free()
	await wait(0.1)

	# ---- D. it passes through the monster layer and the hero's own layer ----------------------
	for case in [["a monster (layer 3)",MONSTER_LAYER],["the hero's own layer (25)",HERO_LAYER]]:
		var label: String = case[0]
		var body = slab(origin+Vector2(40.0,0.0),Vector2(16.0,120.0),int(case[1]))
		await wait(0.1)
		var shot = make_shot(origin)
		var run: Dictionary = await fly(shot,0.40)
		check(run.alive or run.farthest > origin.x+50.0,
			"the projectile is not stopped by %s (reached +%.0f px of +40 px)" % [label,run.farthest-origin.x])
		if is_instance_valid(shot): shot.queue_free()
		body.queue_free()
		await wait(0.15)

	# ---- H. it passes through a REAL monster body, and does not hurt it ------------------------
	var mob = M5Content.spawn("E01",live_arena,origin+Vector2(40.0,0.0))
	check(mob != null,"a real monster spawns in the corridor for the body half")
	if mob != null:
		# Frozen in place and out of its attack loop so the geometry is deterministic. The body,
		# its collision shape and its published layer are the shipped ones: this is the real
		# actor, not a slab that imitates it.
		mob.set_physics_process(false); mob.set_process(false)
		mob.is_die = false
		var mob_layer: int = int(mob.collision_layer)
		var mob_hp: float = float(mob.HP)
		var hp_pos: Vector2 = mob.global_position
		await wait(0.1)
		var shot2 = make_shot(origin)
		shot2.damage = 3.0
		var run2: Dictionary = await fly(shot2,0.40)
		check((mob_layer & SHOT_MASK) == 0,
			"a real monster publishes no layer the shot masks (%d)" % mob_layer)
		check(run2.alive or run2.farthest > origin.x+50.0,
			"the projectile flies straight through a real monster body (reached +%.0f px)"
			% [run2.farthest-origin.x])
		check(absf(float(mob.HP)-mob_hp) < 0.001,
			"...and the monster takes no damage from it (%.1f -> %.1f)" % [mob_hp,float(mob.HP)])
		check(mob.global_position.distance_to(hp_pos) < 2.0,
			"...and is not pushed by it (moved %.2f px)" % mob.global_position.distance_to(hp_pos))
		if is_instance_valid(shot2): shot2.queue_free()
		mob.queue_free()
		await wait(0.15)

	# ---- K. the one behaviour difference, measured rather than argued ---------------------------
	# The mask change is behaviour-preserving ONLY because the old build excluded the hero and every
	# monster that existed when the shot spawned. A monster that spawned afterwards was never
	# excluded, so the old mask DID stop shots on it: the old behaviour depended on spawn order.
	# This section rebuilds that configuration on the shipped node type and measures the delta, so
	# the one real difference this round makes is a pair of numbers rather than a paragraph.
	var late_mob = M5Content.spawn("E01",live_arena,origin+Vector2(40.0,0.0))
	check(late_mob != null,"a real monster spawns in the corridor for the mask-delta half")
	if late_mob != null:
		late_mob.set_physics_process(false); late_mob.set_process(false)
		late_mob.is_die = false
		await wait(0.1)
		# (a) the OLD configuration: old mask, plus the spawn-time exceptions the old code added -
		#     with `late_mob` deliberately left Unexcluded, which is what the old code did for a
		#     monster that did not exist yet.
		var old_shot = make_shot(origin)
		old_shot.collision_mask = SHOT_MASK | 1
		if is_instance_valid(Utils.player): old_shot.add_collision_exception_with(Utils.player)
		for actor in get_tree().get_nodes_in_group("monsters"):
			if actor != late_mob: old_shot.add_collision_exception_with(actor)
		var old_run: Dictionary = await fly(old_shot,0.40)
		check(not old_run.alive or old_run.farthest < origin.x+50.0,
			"old configuration: an unexcluded monster DOES stop the shot, which is why the old "
			+ "behaviour depended on spawn order (+%.0f px of +40 px)" % [old_run.farthest-origin.x])
		if is_instance_valid(old_shot): old_shot.queue_free()
		await wait(0.15)
		# (b) the shipped configuration, same monster, same place, same instant.
		var new_shot = make_shot(origin)
		var new_run: Dictionary = await fly(new_shot,0.40)
		check(new_run.alive or new_run.farthest > origin.x+50.0,
			"shipped configuration: the same monster does not stop the same shot (reached +%.0f px)"
			% [new_run.farthest-origin.x])
		if is_instance_valid(new_shot): new_shot.queue_free()
		late_mob.queue_free()
		await wait(0.15)

	# ---- E. it still STOPS on geometry --------------------------------------------------------
	for case in [["arena geometry (layer 32)",WALL_LAYER],["a town-style slab (layer 1+32)",BUILDING_LAYER]]:
		var label: String = case[0]
		var body = slab(origin+Vector2(40.0,0.0),Vector2(16.0,120.0),int(case[1]))
		await wait(0.1)
		var shot = make_shot(origin)
		var run: Dictionary = await fly(shot,0.40)
		# The wall's near face is at +32 px from the origin, and the shot's own shape is 3 px, so a
		# stopped projectile must not have passed +29 px.
		check(run.farthest < origin.x+32.0,
			"%s stops the projectile on its near face (stopped at +%.0f px of a +32 px face)" % [label,run.farthest-origin.x])
		if is_instance_valid(shot): shot.queue_free()
		body.queue_free()
		await wait(0.15)

	# ---- E2. the LIVE arena's OWN wall stops it (real shipped geometry) ------------------------
	# Found by the authored shape the arena builds in `_ready` (16 x 692), so this fires at the real
	# map rather than at a slab the product never creates. The RIGHT border is used because the
	# shipped projectile always travels +x: aiming at the left wall would fly away from it.
	var border: StaticBody2D = null
	var border_layer := 0
	for node in live_arena.get_children():
		if not (node is StaticBody2D): continue
		if node.get_child_count() == 0: continue
		var cs := node.get_child(0) as CollisionShape2D
		if cs == null: continue
		var box := cs.shape as RectangleShape2D
		if box == null: continue
		if absf(box.size.x-16.0) < 0.01 and absf(box.size.y-692.0) < 0.01 			and node.global_position.x > live_arena.global_position.x:
			border = node as StaticBody2D
			border_layer = int(border.collision_layer)
	check(border != null,"the live arena's own border wall is found by its authored shape")
	check(border != null and border_layer == WALL_LAYER,
		"...and it publishes exactly the shot's layer (%d)" % border_layer)
	if border != null:
		var wall_center: Vector2 = border.global_position
		var near_face: float = wall_center.x-8.0
		var start := Vector2(wall_center.x-68.0,wall_center.y)
		var shot3 = make_shot(start)
		var run3: Dictionary = await fly(shot3,0.60)
		check(run3.farthest > start.x+8.0,
			"the run at the real wall starts in open space, so the stop is not a stuck start (+%.0f px)"
			% [run3.farthest-start.x])
		check(run3.farthest < near_face+SHOT_RADIUS+2.0,
			"the LIVE arena wall stops the projectile on its near face (%.1f < %.1f)"
			% [run3.farthest,near_face+SHOT_RADIUS+2.0])
		if is_instance_valid(shot3): shot3.queue_free()
		await wait(0.15)

	# ---- E3. every authored region obstacle table blocks, at the arena's own layer value -------
	var tables := 0
	var blocked_regions := 0
	for region in REGIONS:
		if not M5Content.WALLS.has(region):
			check(false,"M5Content.WALLS still declares region %s" % region)
			continue
		var rects: Array = M5Content.WALLS[region]
		if rects.is_empty():
			check(false,"region %s still authors at least one obstacle" % region)
			continue
		tables += 1
		var rect: Rect2 = rects[0]
		# Built exactly the way `CombatArena._ready` builds its own: layer 2147483648, mask 0,
		# centred on the authored rect. Only the position is moved, onto the known-clear corridor.
		var body = slab(origin+Vector2(40.0+rect.size.x*0.5,0.0),rect.size,WALL_LAYER)
		await wait(0.08)
		var shot = make_shot(origin)
		var run: Dictionary = await fly(shot,0.40)
		var stopped: bool = run.farthest < origin.x+40.0+SHOT_RADIUS+2.0
		if stopped: blocked_regions += 1
		check(stopped,
			"region %s (%s) blocks the projectile (stopped at +%.0f px of a +40 px face)"
			% [region,str(rect.size),run.farthest-origin.x])
		if is_instance_valid(shot): shot.queue_free()
		body.queue_free()
		await wait(0.10)
	check(tables == REGIONS.size(),"all %d authored regions were exercised (%d)" % [REGIONS.size(),tables])
	check(blocked_regions == tables,"every authored region table blocked the shot (%d/%d)" % [blocked_regions,tables])

	# ---- G. it still REALLY hits the player ----------------------------------------------------
	# The hero is placed exactly on the corridor, so the segment the shot travels this frame passes
	# through it. `onHit` is the product's own entry point and `shot:` is not a throttled source, so
	# a landing projectile must both register and cost health.
	park_player(origin+Vector2(90.0,0.0))
	PlayerData.player_hp = PlayerData.player_hp_max
	await wait(0.2)
	var hp_before: int = int(PlayerData.player_hp)
	var hits_before: int = B11Probe.player_hits
	var live = make_shot(origin)
	live.damage = 1.0
	var g: Dictionary = await fly(live,0.60)
	check(B11Probe.player_hits > hits_before,
		"a projectile that reaches the player still registers a real hit (%d -> %d)"
		% [hits_before,B11Probe.player_hits])
	check(int(PlayerData.player_hp) < hp_before,
		"...and the hit really took health (%d -> %d)" % [hp_before,int(PlayerData.player_hp)])
	check(not is_instance_valid(live),"a projectile that lands is consumed")
	park_player(town.global_position + Vector2(-620.0,-620.0))
	await clean_actors()

	# ---- F. a real sentinel's own projectile, and no exception bookkeeping ---------------------
	#
	# `_begin()` only ARMS a wind-up: it takes the lock and creates the warning footprint. The
	# projectile is not born until the wind-up expires and the live AI runs `perform_attack()`, whose
	# E13 branch ends in `shot(...)` - the shipped factory. Driving that function directly is what
	# makes this an integration half rather than a reconstruction: the actor, the direction, the
	# style, the factory and the mask are all the product's own. (Ticking the real timer instead
	# would test the same `shot()` call plus a state machine that has its own tests, and would make
	# this one flaky on the frames it lands on.)
	var exceptions_before: int = B11Probe.shot_exceptions
	var created_before: int = B11Probe.shot_created
	var sentinel = M5Content.spawn("E13",live_arena,origin+Vector2(120.0,-90.0))
	check(sentinel != null,"a real tremor shooter spawns for the integration half")
	if sentinel != null:
		sentinel.set_physics_process(false)
		sentinel.locked_direction = sentinel.global_position.direction_to(Utils.player.global_position)
		sentinel.attack_kind = "tremor"
		var existing := {}
		for prior in get_tree().get_nodes_in_group("enemy_projectiles"):
			if is_instance_valid(prior): existing[prior.get_instance_id()] = true
		sentinel.perform_attack()
		await wait(0.05)
		var fresh := 0
		for shot in get_tree().get_nodes_in_group("enemy_projectiles"):
			if not is_instance_valid(shot): continue
			if existing.has(shot.get_instance_id()): continue
			fresh += 1
			check(shot.collision_mask == SHOT_MASK,
				"a real sentinel's projectile carries the wall-only mask (%d)" % shot.collision_mask)
		check(fresh > 0,"a real sentinel really did produce projectiles (%d)" % fresh)
		check(B11Probe.shot_created > created_before,
			"the round's own projectile factory recorded the sentinel's shot (created %d -> %d)"
			% [created_before,B11Probe.shot_created])
	await clean_actors()
	check(B11Probe.shot_exceptions == exceptions_before,
		"no per-monster collision exception was added anywhere (rewrite detector: the old fan-out "
		+ "would raise this counter)")

	# ---- J. lifecycle is unchanged -------------------------------------------------------------
	# LAST, because it advances `LevelServer.epoch` and everything spawned after a bump starts on
	# the new one - which is the correct product behaviour and the wrong thing to leave behind.
	# J1 - a new epoch retires the projectiles of the old one.
	var e1 = make_shot(origin)
	check(e1.epoch == LevelServer.epoch,"a fresh projectile records the current epoch")
	await wait(0.1)
	LevelServer.epoch += 1
	await wait(0.15)
	check(not is_instance_valid(e1),"an epoch change still retires the old epoch's projectiles")
	# J2 - the owner dying retires its shots, and only then.
	var owner_body = enemy(origin+Vector2(240.0,-200.0))
	var o1 = make_shot(origin)
	o1.owner_ref = weakref(owner_body)
	await wait(0.12)
	check(is_instance_valid(o1),"a projectile whose owner is alive keeps flying")
	owner_body.is_die = true
	await wait(0.15)
	check(not is_instance_valid(o1),"...and is retired the moment its owner dies")
	# J3 - its own lifetime.
	var l1 = make_shot(origin)
	await wait(0.1)
	check(is_instance_valid(l1),"a projectile younger than 3.2 s is still in flight")
	l1.life = 3.3
	await wait(0.15)
	check(not is_instance_valid(l1),"a projectile still dies of old age at 3.2 s")
	# J4 - the mask survives every retirement path (nothing reset it along the way).
	var survivor = make_shot(origin)
	check(survivor.collision_mask == SHOT_MASK,
		"a projectile spawned after the epoch bump still carries the wall-only mask (%d)"
		% survivor.collision_mask)
	survivor.queue_free()

	await finish()

func finish() -> void:
	for body in bodies:
		if is_instance_valid(body): body.queue_free()
	await clean_actors()
	B11Probe.enabled = false
	print("B11_SHOT_LAYER checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

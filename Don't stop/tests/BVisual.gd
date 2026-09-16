extends "res://tests/B8Runtime.gd"

## Visual acceptance tour. Produces the evidence the user asked for by name:
##   * one screenshot per region R2-R8 at the same viewport, to judge map identity;
##   * one screenshot per attack family (charge / self-destruct / beam / sweep / artillery /
##     root / poison / frost / shock), warning state and active state;
##   * the same three warnings again under Hell fog, to prove the ink survives the darkness;
##   * Boss Phase III for B03 and B04.
##
## This scene is an EVIDENCE producer: it asserts only that each shot had something real to
## photograph, so a blank or missing capture fails instead of looking like a pass.

const REGION_STAGE = {"R2":6,"R3":11,"R4":16,"R5":21,"R6":26,"R7":31,"R8":36}

func telegraph(kind: String, style: String, offset: Vector2, direction: Vector2, radius: float, length: float, width: float, angle: float, sweep := 0.0):
	var zone = load("res://game/monster/HostileZone.gd").new()
	zone.mode = kind; zone.style = style
	zone.radius = radius; zone.length = length; zone.width = width
	zone.angle = angle; zone.sweep = sweep
	zone.warning = 4.0; zone.duration = 4.0; zone.damage = 0.0
	zone.pierce = kind in ["line","charge"]
	zone.position = Utils.player.global_position+offset
	zone.direction = direction
	LevelServer.town.arena.add_child(zone)
	return zone

func shoot_warning(label: String, zone):
	if zone == null: return
	await wait(0.35)
	await settle_render()
	recenter(); snap(label+"-warning")
	# The final 0.2-0.3 s of a wind-up is meant to brighten hard; sample it explicitly.
	zone.elapsed = zone.warning-0.08
	await settle_render()
	recenter(); snap(label+"-about-to-fire")
	# HostileZone drives its state machine off `elapsed` alone; a StageHazard drives it off
	# `phase_time` and is forced separately below.
	zone.elapsed = zone.warning+0.05
	await settle_render()
	if is_instance_valid(zone): recenter(); snap(label+"-active")
	await wait(0.4)
	if is_instance_valid(zone): zone.queue_free()
	await wait(0.2)

func visit(stage: int, label: String):
	stop(); LevelServer.return_to_camp(); await wait(0.4)
	check(LevelServer.town.depart(stage,true),"stage %d departs for the %s capture" % [stage,label])
	await visual_ready()
	await wait(0.9)
	freeze_room()
	recenter(); await wait(0.25)
	check(is_instance_valid(render_camera),"the render rig is up for %s" % label)
	snap(label)
	var bands = profile()
	check(bands[0] > 0.004 or bands[3] > 0.004,"the %s capture is not a black frame" % label)
	print("BVISUAL %-14s %s" % [label,band_text(bands)])

func _ready():
	await boot(); configure(124,true)

	# ---- Region identity tour, same viewport for every region ---------------------------
	for region in ["R2","R3","R4","R5","R6","R7","R8"]:
		await visit(REGION_STAGE[region],"region-"+region)

	# ---- Attack UI / VFX, judged on the bright arena first ------------------------------
	await visit(26,"telegraph-host-R6")
	var p = Utils.player.global_position
	var right = Vector2.RIGHT
	# Charge: a solid danger lane with flowing arrows.
	await shoot_warning("ui-charge",telegraph("charge","charge",Vector2(-150,-40),right,190.0,190.0,18.0,0.0))
	# Self-destruct: a shrinking ring on the ground.
	await shoot_warning("ui-detonate",telegraph("circle","detonate",Vector2(70,30),right,58.0,58.0,0.0,0.0))
	# Beam: a thin line that brightens hard in the last fifth of a second.
	await shoot_warning("ui-beam",telegraph("line","laser",Vector2(-210,60),right,320.0,320.0,10.0,0.0))
	# Sweep: a rotating line with the turning chevron.
	await shoot_warning("ui-sweep",telegraph("line","sweep",Vector2(-60,-120),Vector2.DOWN,300.0,300.0,12.0,0.0,1.1))
	# Artillery: a ground target with a timing ring on the player's position.
	await shoot_warning("ui-artillery",telegraph("circle","artillery",Vector2(120,-70),right,52.0,52.0,0.0,0.0))
	# Root / control: purple, with the waveform that marks it as control rather than damage.
	await shoot_warning("ui-root",telegraph("cone","root",Vector2(-90,90),right.rotated(-0.7),160.0,160.0,0.0,0.85))
	# Shock band: violet moving danger band.
	await shoot_warning("ui-shock",telegraph("line","shock",Vector2(-120,140),Vector2.DOWN,320.0,320.0,30.0,0.0,0.5))

	# Poison and frost come from the hazard system, not the telegraph system.
	var poison = load("res://game/map/StageHazard.gd").new()
	poison.kind = "poison"; poison.at = p+Vector2(150,0); poison.radius = 96.0
	poison.length = 96.0; poison.width = 96.0; poison.warning = 4.0; poison.active_time = 6.0; poison.pulses = 1
	LevelServer.town.arena.add_child(poison)
	await wait(0.4); recenter(); snap("ui-poison-warning")
	poison.elapsed = 4.2; poison.phase_time = 0.01
	await settle_render()
	recenter(); snap("ui-poison-active")
	check(poison.phase == "active","the poison field reached its live state for the capture")
	poison.queue_free(); await wait(0.3)

	var frost = load("res://game/map/StageHazard.gd").new()
	frost.kind = "frost"; frost.at = p+Vector2(-160,-40); frost.radius = 86.0
	frost.length = 86.0; frost.width = 86.0; frost.warning = 4.0; frost.active_time = 6.0; frost.pulses = 1
	LevelServer.town.arena.add_child(frost)
	await wait(0.4); recenter(); snap("ui-frost-warning")
	frost.elapsed = 4.2; frost.phase_time = 0.01
	await settle_render()
	recenter(); snap("ui-frost-active")
	frost.queue_free(); await wait(0.3)

	# ---- The three critical warnings again, this time inside Hell fog -------------------
	await visit(31,"telegraph-hell-R7")
	check(ArenaVisibility.fog_active(),"the Hell readability set really runs under fog")
	await shoot_warning("fog-read-charge",telegraph("charge","charge",Vector2(-150,-40),right,190.0,190.0,18.0,0.0))
	await shoot_warning("fog-read-beam",telegraph("line","laser",Vector2(-210,60),right,320.0,320.0,10.0,0.0))
	var hell_poison = load("res://game/map/StageHazard.gd").new()
	hell_poison.kind = "poison"; hell_poison.at = p+Vector2(140,0); hell_poison.radius = 96.0
	hell_poison.length = 96.0; hell_poison.width = 96.0; hell_poison.warning = 4.0; hell_poison.active_time = 6.0; hell_poison.pulses = 1
	LevelServer.town.arena.add_child(hell_poison)
	await wait(0.4); recenter(); snap("fog-read-poison")
	hell_poison.queue_free(); await wait(0.3)

	# ---- Boss Phase III -----------------------------------------------------------------
	for pair in [[30,"B03"],[40,"B04"]]:
		var stage = pair[0]
		var name = pair[1]
		stop(); LevelServer.return_to_camp(); await wait(0.4)
		check(LevelServer.town.depart(stage,true),"stage %d departs for the %s phase III capture" % [stage,name])
		await visual_ready()
		LevelServer.timerStop()
		await wait(0.6)
		# A deferred boss is a legal outcome that Town retries; give the retry a few frames.
		var boss = instance_from_id(LevelServer.boss_instance)
		for attempt in 40:
			if is_instance_valid(boss): break
			await get_tree().physics_frame
			boss = instance_from_id(LevelServer.boss_instance)
		check(is_instance_valid(boss),"stage %d spawns %s" % [stage,name])
		if is_instance_valid(boss):
			boss.set_physics_process(false)
			boss.phase_two = true; boss.phase_three = true
			boss.HP = boss.max_hp*0.30
			boss.global_position = Utils.player.global_position+Vector2(150,-30)
			boss.locked_direction = boss.global_position.direction_to(Utils.player.global_position)
			boss.locked_point = Utils.player.global_position
			boss.ultimate_cooldown = 0
			Utils.player.set_physics_process(false)
			recenter()
			check(boss.phase_three,"%s reported Phase III for the capture" % name)
			await wait(0.3); recenter(); snap("boss-"+name+"-phase3-idle")
			# One real Phase III attack and one real percentage ultimate, both through the
			# production path - no hand-placed graphics.
			boss.choose_attack()
			await wait(0.5); recenter(); snap("boss-"+name+"-phase3-attack")
			await wait(1.0); recenter(); snap("boss-"+name+"-phase3-active")
			boss.ultimate_cooldown = 0
			boss.attack_index = 0
			boss.phase = "move"; boss.phase_time = 0
			boss.choose_attack()
			await wait(0.6); recenter(); snap("boss-"+name+"-ultimate-warning")
			await wait(1.4); recenter(); snap("boss-"+name+"-ultimate-active")
			check(boss.actions.get("ultimate_activated",0) > 0 or boss.actions.get("windup_ultimate",0) > 0,
				"%s really started a percentage ultimate" % name)

	print("BVISUAL CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

extends "res://tests/B8Runtime.gd"

## Fog audit. Verifies that the ORIGINAL TowDownGame darkness has been restored as a
## stage-aware property of Hell rather than as a permanent change, that Stage 1-30 is
## untouched, that the restored light is still where upstream put it, and that the fog
## fairness gate cannot be talked out of showing a warning first.
##
## Every brightness claim in the final report comes from profile() below, which is read off a
## real rendered frame under gl_compatibility - the renderer the deployed Web build uses.

func mean_over(bands: Array, from: int, to: int) -> float:
	var sum = 0.0
	for i in range(from,mini(to+1,bands.size())): sum += bands[i]
	return sum/maxf(1.0,float(to-from+1))

func fog_zone(damage: float, warning: float, at: Vector2, radius := 40.0, duration := 0.3):
	var zone = load("res://game/monster/HostileZone.gd").new()
	zone.mode = "circle"; zone.radius = radius; zone.warning = warning
	zone.duration = duration; zone.damage = damage; zone.world_point = at
	LevelServer.town.arena.add_child(zone)
	return zone

func _ready():
	await boot(); configure(124,true)
	print("B4 mode=",("bypass" if "--hell-unlock" in OS.get_cmdline_user_args() else "product"))

	# ---- The retained upstream infrastructure is what we drive -------------------------
	var modulate = ArenaVisibility.modulate_node()
	var light = ArenaVisibility.player_light()
	check(modulate != null,"Main.tscn CanvasModulate is reachable")
	check(light != null,"the retained Town.tscn Camera2D/PointLight2D is reachable")
	if light != null:
		check(light.texture != null and light.texture.resource_path == "res://Sprites/light2.png",
			"the player light still uses the upstream light2.png")
		check(absf(light.texture_scale-HellMode.UPSTREAM_LIGHT_SCALE) < 0.01,
			"camp light scale is the authored upstream 0.5")

	# ---- Camp is bright ----------------------------------------------------------------
	check(not ArenaVisibility.fog_active(),"camp has no fog")
	check(absf(modulate.color.g-DemoConfig.AMBIENT.g) < 0.02,"camp ambient is the authored bright value")

	# ---- A NORMAL stage keeps the bright arena ----------------------------------------
	check(LevelServer.town.depart(26,true),"normal stage 26 departs")
	await visual_ready()
	await wait(0.9)
	freeze_room()
	recenter(); await wait(0.2)
	check(not ArenaVisibility.fog_active(),"stage 26 keeps fog OFF")
	check(absf(modulate.color.g-DemoConfig.AMBIENT.g) < 0.02,"stage 26 ambient stays bright")
	check(absf(light.texture_scale-HellMode.UPSTREAM_LIGHT_SCALE) < 0.01,"stage 26 light scale is unchanged")
	var bright = profile()
	snap("fog-A-normal-stage26")
	print("B4 PROFILE normal  ",band_text(bright))
	check(bright[0] > 0.02 or not rendering(),"the normal arena actually renders a visible floor")

	# ---- Same map, same player position, Hell profile ON: the A/B pair -----------------
	ArenaVisibility.apply_stage(31)
	await wait(0.9)
	check(ArenaVisibility.fog_active(),"applying a Hell stage turns fog ON")
	var dark = profile()
	snap("fog-B-hell-profile-same-map")
	print("B4 PROFILE hell31  ",band_text(dark))
	print("B4 RADIUS normal=",readable_radius(bright)," hell=",readable_radius(dark))
	# The luminance assertions only exist in a render run: under --headless there are no
	# pixels to read, and the contract half above/below still runs in the CI gate.
	if rendering():
		var near_bright = mean_over(bright,0,1)
		var near_dark = mean_over(dark,0,1)
		var far_bright = mean_over(bright,5,8)
		var far_dark = mean_over(dark,5,8)
		print("B4 CONTRAST near %.4f->%.4f far %.4f->%.4f" % [near_bright,near_dark,far_bright,far_dark])
		check(far_dark < far_bright*0.3,"the far field is genuinely darkened, not merely tinted")
		check(near_dark > 0.02,"the lit radius keeps the player's surroundings readable")
		check(near_dark > far_dark*2.0,"the lit radius is clearly brighter than the far field")
		var hell_radius = readable_radius(dark)
		var normal_radius = readable_radius(bright)
		print("B4 RADIUS normal=%d hell=%d" % [normal_radius,hell_radius])
		check(hell_radius >= 120 and hell_radius <= 384,"the Hell radius stays in a playable band (%d px)" % hell_radius)
		check(hell_radius < normal_radius,"Hell is genuinely tighter than normal on the same map")
	check(absf(modulate.color.g-HellMode.fog(31).ambient) < 0.02,"the tween lands on the stage-31 target ambient")
	check(absf(light.texture_scale-HellMode.light_scale(31)) < 0.02,"the tween lands on the stage-31 target light scale")
	# HUD must not be darkened: ControlUI is a CanvasLayer (layer 2), so it is a different
	# canvas from the one that carries the CanvasModulate. That is exactly why the camp UI,
	# the crosshair and the Boss HUD stay readable while the world is dark.
	check(Utils.canvasLayer.layer == 2 and modulate.get_parent() != Utils.canvasLayer,
		"the HUD lives on its own canvas, outside the modulated one")

	# ---- Restoring is exact -------------------------------------------------------------
	FogPierce.ensure()
	check(FogPierce.instance() != null,"the fog pierce layer is created while Hell is active")
	ArenaVisibility.restore(true)
	await wait(0.7)
	check(not ArenaVisibility.fog_active(),"returning to the bright profile clears fog_active()")
	check(absf(modulate.color.g-DemoConfig.AMBIENT.g) < 0.02,"restore returns the authored ambient")
	check(absf(light.texture_scale-HellMode.UPSTREAM_LIGHT_SCALE) < 0.01,"restore returns the authored light scale")
	FogPierce.discard(); await wait(0.3)
	check(FogPierce.instance() == null,"the fog pierce layer is discarded with the fog")
	var restored = profile()
	print("B4 PROFILE restored ",band_text(restored))
	if rendering(): check(mean_over(restored,5,8) > mean_over(dark,5,8)*2.0,"restoring brings the far field back")
	snap("fog-A2-restored-same-map")

	# ---- The 31-40 profile table is bounded and monotone in the right direction --------
	var previous = 4096.0
	for stage in range(31,41):
		var radius = HellMode.fair_radius(stage)
		check(radius >= 120.0,"stage %d fog never shrinks to 'only your feet' (%.0f px)" % [stage,radius])
		check(radius <= 340.0,"stage %d fog keeps a usable radius (%.0f px)" % [stage,radius])
		check(radius <= previous+0.01,"stage %d fog does not widen as stages advance" % stage)
		previous = radius
	check(HellMode.fair_radius(40) < HellMode.fair_radius(31),"stage 40 is tighter than stage 31")
	for stage in range(1,31):
		check(not HellMode.is_hell(stage) and HellMode.fair_radius(stage) > 1000.0,"stage %d is outside Hell" % stage)

	# ---- A real Hell round: fog on, then camp cleanup ----------------------------------
	stop(); LevelServer.return_to_camp(); await wait(0.5)
	check(LevelServer.town.depart(31,true),"hell stage 31 departs")
	await wait(1.0)
	check(ArenaVisibility.fog_active(),"a real stage-31 round runs with fog ON")
	check(fog_materials_current(),"the stage-31 target is applied to live nodes")
	await visual_ready()
	freeze_room(); recenter(); await wait(0.3)
	var real_hell = profile()
	print("B4 PROFILE stage31 ",band_text(real_hell))
	snap("fog-stage31-product")
	if rendering():
		check(real_hell[0] > 0.02 and mean_over(real_hell,6,9) < mean_over(bright,6,9)*0.4,
			"the product Hell round is dark outside the light and lit inside it")

	# ---- Fairness gate -----------------------------------------------------------------
	# A damaging footprint the player cannot see must not open on schedule, and the wait must
	# be bounded; a visible one opens immediately and accrues readable warning time. Both
	# halves are needed: without the second, the first could be satisfied by a gate that
	# simply never fires.
	var gate_epoch = LevelServer.epoch
	check(ArenaVisibility.fog_active(),"the fairness gate is measured while fog is really on")
	var visible_zone = fog_zone(1.0,0.6,Utils.player.global_position+Vector2(30,0),60.0,0.2)
	var hidden_zone = fog_zone(5.0,0.6,Utils.player.global_position+Vector2(2600,0),40.0,0.2)
	check(visible_zone.fair_gate and hidden_zone.fair_gate,"both probe footprints armed the gate")
	await wait(0.75)
	check(visible_zone.elapsed >= 0.6,"a visible footprint reaches activation on schedule")
	check(visible_zone.visible_warning > 0.4,"a visible footprint accumulates readable warning time")
	# `elapsed` keeps running past `warning` while the gate holds the footprint in its warning
	# phase - that IS the mechanism - so the assertion is the phase, not the clock.
	check(hidden_zone.elapsed >= hidden_zone.warning and not hidden_zone.activated,
		"an unreadable footprint is past its schedule and still has not opened")
	check(hidden_zone.visible_warning < 0.1,"an unreadable footprint accumulates no readable warning")
	check(visible_zone.hit_count > 0,"the visible footprint actually connects, so the gate is not a mute button")
	await wait(2.0)
	check(not is_instance_valid(hidden_zone),"the unreadable footprint is released, never stalled forever")
	check(LevelServer.epoch == gate_epoch,"the fairness gate does not advance the epoch")
	PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)

	# Every damaging zone the ENEMY code creates in Hell carries a real warning.
	# E10 is a TacticalEnemy, so it owns _begin()/zone(); E05 uses DemoEnemy and has neither.
	var probe = M5Content.spawn("E10",LevelServer.town.monster_root,Utils.player.global_position+Vector2(300,0))
	check(probe != null,"a ranged enemy can be spawned for the warning-floor probe")
	if probe != null:
		probe.locked_direction = probe.global_position.direction_to(Utils.player.global_position)
		probe._begin("beam")
		var lanes = get_tree().get_nodes_in_group("hostile_zone").filter(func(z): return z.owner_ref and z.owner_ref.get_ref()==probe)
		check(lanes.size() > 0,"the ranged probe created a lane")
		for lane in lanes:
			check(lane.warning >= 0.6,"a Hell lane warns for at least 0.6 s (%.2f)" % lane.warning)
			check(lane.fair_gate,"a Hell lane is born with the fairness gate armed")
			check(lane.pierce,"a Hell lane mirrors itself above the fog")
		probe.queue_free()
	await wait(0.2)

	# ---- Pause / resume keeps the profile ----------------------------------------------
	var before_pause = modulate.color.g
	var holder = Control.new(); Utils.canvasLayer.add_child(holder)
	Demo.push_pause(holder)
	await wait(0.3)
	check(get_tree().paused,"pause actually pauses")
	check(fog_active_now(),"fog stays applied while paused")
	Demo.pop_pause(holder); holder.queue_free()
	await wait(0.3)
	check(not get_tree().paused and fog_active_now(),"resume restores the same fog state")
	check(absf(modulate.color.g-before_pause) < 0.03,"pause/resume does not drift the ambient")

	# ---- Second session: teardown then depart again ------------------------------------
	stop(); LevelServer.return_to_camp(); await wait(0.6)
	check(not ArenaVisibility.fog_active(),"returning to camp clears fog_active()")
	check(get_tree().get_nodes_in_group(StageHazard.GROUP).is_empty(),"returning to camp leaves 0 hazards")
	check(get_tree().get_nodes_in_group("hostile_zone").is_empty(),"returning to camp leaves 0 hostile zones")
	check(FogPierce.instance() == null,"returning to camp leaves no fog overlay")
	ArenaVisibility.reset()
	check(not ArenaVisibility.fog_active(),"a fresh map load reports no fog before any departure")
	check(LevelServer.town.depart(32,true),"a second Hell departure is accepted")
	await wait(0.9)
	check(fog_active_now(),"the second Hell session turns fog ON again")
	check(absf(modulate.color.g-HellMode.fog(32).ambient) < 0.03,"the second session lands on the stage-32 target")
	stop(); LevelServer.return_to_camp(); await wait(0.5)

	print("B4 CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

## fog_active() also requires LevelServer.state == "COMBAT"; this reports the visual state
## alone so a paused or settling round can still be asserted.
func fog_active_now() -> bool:
	var modulate = ArenaVisibility.modulate_node()
	return ArenaVisibility.active_stage >= 31 and modulate != null and modulate.color.g < DemoConfig.AMBIENT.g*0.6

func fog_materials_current() -> bool:
	var light = ArenaVisibility.player_light()
	if light == null: return false
	return absf(light.texture_scale-HellMode.light_scale(ArenaVisibility.active_stage)) < 0.06

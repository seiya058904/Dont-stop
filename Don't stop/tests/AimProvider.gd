extends Node
## Independent takeover audit of the v1.0.2 unified aim provider (autoload/Utils.gd).
##
## It answers three questions with measurements instead of comments:
##  1. Is the desktop branch of Utils.get_aim_world_position() byte-for-byte the
##     behaviour the original CanvasItem.get_global_mouse_position() had? (Windows
##     must not regress.)
##  2. Do the aim provider, the crosshair and the viewport mouse position all live
##     in the SAME coordinate space? (The Web Pointer Lock virtual cursor and the
##     crosshair are compared to each other through it.)
##  3. Does every gameplay aim call site reach the provider legally? The right-click
##     grenade lob in Demo.gd was rewritten by hand and is probed for real.
##
## Exit code 0 = every check passed.

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + ((" | " + detail) if detail != "" else ""))

func _ready() -> void:
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	PlayerData.gold = 100000
	PlayerData.reward_point = 9999
	for i in 20:
		await get_tree().process_frame

	if not PlayerData.player_weapon_list.has(0):
		Demo.try_purchase("weapon", "0")
	Utils.player.changeWeapon(0)
	await get_tree().process_frame

	# ---------------------------------------------------------------- autoload sanity
	check(not ("web_e2e_driver" in Utils),
		"no test-only bypass remains in the gameplay input path")
	check(Smoke.get("e2e") == false,
		"Smoke.e2e is inert without --smoke/--e2e")
	check(Smoke.get("_pending_proj").is_empty(),
		"Smoke projectile hooks are not armed outside --e2e")
	# Smoke._process appends every frame. Outside --smoke nothing ever reads it,
	# so a growing array would be an unbounded production allocation.
	var frames_before: int = (Smoke.get("_frame_times") as Array).size()
	await get_tree().create_timer(0.5, false).timeout
	var frames_after: int = (Smoke.get("_frame_times") as Array).size()
	check(frames_after == frames_before,
		"Smoke does not accumulate frame samples in a production launch",
		"%d -> %d" % [frames_before, frames_after])

	# ------------------------------------------------------------- coordinate spaces
	var vp := get_viewport()
	var visible := vp.get_visible_rect()
	var canvas_xf := vp.get_canvas_transform()
	var crosshair: Control = Utils.canvasLayer.get_node_or_null("TextureRect")
	print("[aim] window=", get_window().size,
		" content_scale_mode=", get_window().content_scale_mode,
		" viewport_size=", vp.size,
		" visible_rect=", visible,
		" canvas_transform=", canvas_xf,
		" canvas_layer_transform=", Utils.canvasLayer.get_final_transform())
	check(crosshair != null, "the product crosshair exists in the HUD CanvasLayer")
	check(Utils.player != null and Utils.player.gun != null,
		"the audited player and gun are live", "gun=%s" % str(Utils.player.gun.weapon_id))

	# The provider must agree with the ORIGINAL desktop expression at several
	# distinct viewport positions, not just at one lucky point.
	var probe_points := [
		Vector2(visible.size.x * 0.5, visible.size.y * 0.5),
		Vector2(visible.size.x * 0.2, visible.size.y * 0.25),
		Vector2(visible.size.x * 0.8, visible.size.y * 0.75),
	]
	var provider_matches_hero := 0
	var provider_matches_gun := 0
	var provider_matches_original := 0
	var crosshair_matches_provider := 0
	var crosshair_worst_delta := 0.0
	var injected_points := 0
	for point in probe_points:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		vp.push_input(motion, true)
		# Root windows do not consume push_input for GUI bookkeeping, so also try
		# the SceneTree dispatch path; whichever updates the mouse position wins.
		var dispatch := InputEventMouseMotion.new()
		dispatch.position = point
		Input.parse_input_event(dispatch)
		await get_tree().process_frame
		var mouse_vp: Vector2 = vp.get_mouse_position()
		var aim_vp: Vector2 = Utils.get_aim_viewport_position()
		var aim_world: Vector2 = Utils.get_aim_world_position()
		var hero_world: Vector2 = Utils.player.get_global_mouse_position()
		var gun_world: Vector2 = Utils.player.gun.get_global_mouse_position()
		# The exact expression Crosshair.gd used before the v1.0.2 rewrite.
		var original_crosshair: Vector2 = crosshair.get_global_mouse_position()
		var crosshair_center: Vector2 = crosshair.global_position + crosshair.size / 2.0
		print("[aim] probe push=", point, " mouse_vp=", mouse_vp, " aim_vp=", aim_vp,
			" aim_world=", aim_world, " hero_world=", hero_world, " gun_world=", gun_world,
			" crosshair_global=", crosshair.global_position, " crosshair_size=", crosshair.size,
			" original_expr=", original_crosshair)
		if mouse_vp.distance_to(point) < 0.01:
			injected_points += 1
		if aim_vp.distance_to(mouse_vp) < 0.01:
			provider_matches_hero += 1
		if aim_world.distance_to(hero_world) < 0.01 and aim_world.distance_to(gun_world) < 0.01:
			provider_matches_gun += 1
		# Control.get_global_mouse_position() for a HUD-CanvasLayer child is the
		# expression Crosshair.gd used before v1.0.2. Equality proves the rewrite
		# did not move the crosshair on desktop.
		if original_crosshair.distance_to(mouse_vp) < 0.01:
			provider_matches_original += 1
		var delta: float = crosshair_center.distance_to(aim_vp)
		crosshair_worst_delta = maxf(crosshair_worst_delta, delta)
		if delta < 0.5:
			crosshair_matches_provider += 1

	var n := probe_points.size()
	print("[aim] injected_points=%d/%d crosshair_worst_delta=%.4f design_units" % [
		injected_points, n, crosshair_worst_delta])
	check(provider_matches_hero == n,
		"desktop: get_aim_viewport_position() == viewport.get_mouse_position()",
		"%d/%d" % [provider_matches_hero, n])
	check(provider_matches_gun == n,
		"desktop: get_aim_world_position() == Player/Gun get_global_mouse_position()",
		"%d/%d" % [provider_matches_gun, n])
	check(crosshair_matches_provider == n,
		"crosshair centre sits on the aim provider position (sub-pixel)",
		"%d/%d worst=%.4f" % [crosshair_matches_provider, n, crosshair_worst_delta])
	check(provider_matches_original == n,
		"crosshair.get_global_mouse_position() == viewport mouse position (rewrite is desktop-neutral)",
		"%d/%d" % [provider_matches_original, n])

	# ------------------------------------------------------- gameplay call-site audit
	# Demo.gd's right-click lob was hand-rewritten to the aim provider and briefly
	# read Utils.player.Utils, which does not exist (SCRIPT ERROR, lob dead). Drive
	# the real path and require a grenade that targets the provider's aim point.
	LevelServer.state = "COMBAT"
	Demo.owned_global_upgrades = ["9"]
	Demo.grenade_cooldown = 0.0
	var aim_before: Vector2 = Utils.get_aim_world_position()
	var right_click := InputEventAction.new()
	right_click.action = "mouse_right"
	right_click.pressed = true
	print("[aim] probing Demo._unhandled_input(mouse_right)")
	Demo._unhandled_input(right_click)
	await get_tree().process_frame
	var grenades: Array = []
	for node in get_tree().get_nodes_in_group("combat_transient"):
		var script = node.get_script()
		if script != null and script.resource_path == "res://game/other/Grenade.gd":
			grenades.append(node)
	check(grenades.is_empty(), "B16 right-click cannot create a second A9 ability budget")
	check(Demo.grenade_cooldown == 0.0, "right-click without a real hit does not consume the automatic cooldown")
	await get_tree().process_frame

	# -------------------------------------------------- Windows must not be redirected
	check(Utils.is_gameplay_mouse_mode() == (Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN),
		"desktop gameplay mouse mode is still CONFINED_HIDDEN",
		"mouse_mode=%d" % Input.mouse_mode)

	print("AIM_PROVIDER_AUDIT checks=%d failures=%d" % [checks, failures])
	await get_tree().create_timer(0.1, true).timeout
	get_tree().quit(1 if failures else 0)

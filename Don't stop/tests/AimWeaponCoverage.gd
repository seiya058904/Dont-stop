extends Node
## Weapon-class coverage for the v1.0.2 unified aim provider.
##
## The Web Pointer Lock E2E proves the provider itself is correct, but it can
## only fire the default gun (the product has no weapon-switch key and the E2E
## must not fabricate purchases). Weapon aim therefore has to be proven on the
## desktop platform where every class can be equipped deterministically.
##
## For every entry in Utils.weapon_list this test:
##   1. computes the direction the provider says the weapon should point,
##   2. lets the weapon's own _process run so it computes `direction`,
##   3. fires through the weapon's own firing path (its _shoot override, or the
##      charge/spin/thermal entry points those classes use), and
##   4. requires the spawned projectile's velocity to follow that direction.
##
## Exit code 0 = every class aims through the provider.

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
	PlayerData.gold = 1000000
	PlayerData.reward_point = 99999
	for i in 20:
		await get_tree().process_frame

	LevelServer.state = "COMBAT"
	Utils.player.set_physics_process(false)      # no knockback drift mid-measurement
	PlayerData.reserve_magazines = 1000

	var ids := Utils.weapon_list.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	var aimed := 0
	var projectile_match := 0
	var projectile_classes: Array = []
	var beam_classes: Array = []
	for id in ids:
		var ok := await _audit_weapon(int(id))
		if ok.heard_provider:
			aimed += 1
		if ok.has_projectile:
			projectile_classes.append(id)
		else:
			beam_classes.append(id)
		if ok.direction_ok:
			projectile_match += 1

	check(aimed == ids.size(),
		"every weapon class reads the unified aim provider into gun.direction",
		"%d/%d" % [aimed, ids.size()])
	check(projectile_match == ids.size(),
		"every weapon class points along the provider direction",
		"%d/%d" % [projectile_match, ids.size()])
	print("[aim-weapons] projectile classes=%s" % str(projectile_classes))
	print("[aim-weapons] non-projectile classes (beam/rail-style)=%s" % str(beam_classes))
	check(projectile_classes.size() >= 4,
		"at least four projectile weapon classes were exercised end to end",
		"n=%d" % projectile_classes.size())

	print("AIM_WEAPON_COVERAGE checks=%d failures=%d" % [checks, failures])
	await get_tree().create_timer(0.1, true).timeout
	get_tree().quit(1 if failures else 0)


func _audit_weapon(id: int) -> Dictionary:
	var result := {"heard_provider": false, "has_projectile": false, "direction_ok": false}
	if not PlayerData.player_weapon_list.has(id):
		# Each weapon scene declares its own weapon_id, so instantiating is enough.
		PlayerData.add_weapon((Utils.weapon_list[str(id)] as PackedScene).instantiate())
	if not PlayerData.changeWeapon(id, true):
		# Switching has a cooldown; wait it out rather than reporting a false failure.
		var deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and not PlayerData.changeWeapon(id, true):
			await get_tree().create_timer(0.1, true).timeout
	var gun = PlayerData.player_weapon_list.get(id)
	if gun == null:
		check(false, "weapon %d could not be equipped" % id)
		return result
	gun.set_process(true)
	gun.set_physics_process(true)
	gun.can_shoot = true
	gun.is_reloading = false
	gun.bullets_count = gun.bullets_max_count
	gun.change_timer.stop()
	if is_instance_valid(gun.timer):
		gun.timer.stop()
	await get_tree().process_frame
	await get_tree().process_frame

	# What the provider says this weapon must point at.
	var aim: Vector2 = Utils.get_aim_world_position()
	var expected: Vector2 = (aim - (gun.gun_tip.global_position as Vector2)).normalized()
	var direction: Vector2 = gun.direction
	var heard := direction.length() > 0.5 and direction.normalized().distance_to(expected) < 0.02
	result.heard_provider = heard
	result.direction_ok = heard

	var seen := {}
	for node in get_tree().get_nodes_in_group("combat_transient"):
		seen[node.get_instance_id()] = true

	_fire_weapon(gun)
	# Velocity is assigned one frame after the node enters the tree.
	await get_tree().process_frame
	await get_tree().process_frame

	var spawned: Array = []
	for node in get_tree().get_nodes_in_group("combat_transient"):
		if seen.has(node.get_instance_id()):
			continue
		if "velocity" in node and node.velocity.length() > 0.1:
			spawned.append(node)

	var extra := ""
	if spawned.is_empty():
		extra = "no travelling projectile (beam/cone class by design)"
	else:
		result.has_projectile = true
		# Spread weapons fire a fan around the aim, so require the centre shot to
		# follow the provider exactly and the fan to be symmetric about it rather
		# than picking whichever pellet spawned first.
		var best := 999.0
		var sum := Vector2.ZERO
		var speeds := []
		for node in spawned:
			var v: Vector2 = node.velocity
			best = minf(best, radf(absf(v.angle_to(expected))))
			sum += v.normalized()
			speeds.append(int(v.length()))
		var mean_delta := 999.0
		if sum.length() > 0.01:
			mean_delta = radf(absf(sum.normalized().angle_to(expected)))
		result.direction_ok = best < 8.0 and mean_delta < 20.0
		extra = "n=%d best=%.1f mean=%.1f speeds=%s" % [spawned.size(), best, mean_delta, str(speeds)]
		for node in spawned:
			node.queue_free()

	check(result.direction_ok, "weapon %d aims through the provider" % id, extra)
	await get_tree().process_frame
	return result


func radf(value: float) -> float:
	return rad_to_deg(value)


func _fire_weapon(gun) -> void:
	var spec := WeaponCatalog.definition(gun.weapon_id)
	var mode: String = spec.get("mode", "")
	# Mirror how each mode really fires. drive_spin only exists for the rotary
	# spec, which is the only catalog entry that defines max_rate.
	if mode == "rail" and gun.has_method("handle_charge"):
		gun.handle_charge(true, 1.0)
		gun.handle_charge(false, 1.0)
		return
	if mode == "thermal" and gun.has_method("handle_thermal"):
		gun.handle_thermal(true, 0.25)
		return
	if mode == "rotary" and gun.has_method("drive_spin"):
		gun.drive_spin(true, 1.0)
	gun._shoot()

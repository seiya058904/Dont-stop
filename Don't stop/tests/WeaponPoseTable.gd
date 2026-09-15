extends Node

## A3: every weapon must hold a stable pose and fire from its own muzzle.
##
## The reported symptom was BabyZapZap (weapon_id 3) riding higher than the hand.
## The cause was not a wrong offset in Baby's scene: it was the recoil animation.
## BaseGun._shootAnim() started a fresh Tween on every shot whose target was the
## gun's *current* position. If the previous animation had not finished, the next
## one inherited that half-moved position as its destination, so the gun advanced
## a little each shot and walked up out of the hand. Baby was the worst case only
## because it asks for the animation once per pellet (three times per trigger), so
## it ran out of animation long before it ran out of trigger pulls.
##
## The fix is an anchor: the gun records its resting pose once and every recoil is
## a temporary offset that always resolves back to that anchor, owned by a single
## mutually-exclusive tween.
##
## Part 1 walks all 24 weapons in Utils.weapon_list and checks the contract with no
## session involved: the anchor exists, the muzzle exists and owns the flash, and
## rapid fire never drifts. Part 2 starts a real session and proves the projectiles
## are born at the muzzle rather than somewhere the flash is not.
##
## Run headless:
##   Godot_v4.7.2-stable_win64.exe --headless --path <project> res://tests/WeaponPoseTable.tscn

static var _probe_spawned := false

const MENU_SCENE := "res://game/map/Main.tscn"
const DRIFT_EPSILON := 0.01
## The default recoil offset is Vector2(-1, -1); nothing may push the gun further
## than that from its anchor while the animation plays.
const MAX_ANIM_OFFSET := 2.0
const RAPID_SHOTS := 60

## The weapons the muzzle check drives for real. Baby is the reported one; the
## rest are one of each firing shape (single, burst, shotgun, machine gun).
const MUZZLE_WEAPONS := [3, 0, 2, 1, 9]

var _failures := 0
var _checks := 0

func _ready() -> void:
	if _probe_spawned:
		_run.call_deferred()
		return
	_probe_spawned = true
	var probe := Node.new()
	probe.name = "WeaponPoseTableProbe"
	probe.set_script(load("res://tests/WeaponPoseTable.gd"))
	get_tree().root.add_child.call_deferred(probe)

func _watchdog() -> void:
	await get_tree().create_timer(240.0, true).timeout
	print("POSE_RESULT=TIMEOUT after 240s")
	get_tree().quit(2)

func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok: _failures += 1
	print("POSE %s %s%s" % ["ok  " if ok else "FAIL", label, (" :: " + detail) if detail != "" else ""])

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _run() -> void:
	_watchdog()
	await _part1_pose_table()
	await _part2_muzzle_origin()
	_finish()

## ---------------------------------------------------------------- part 1 ----

func _part1_pose_table() -> void:
	var host := Node2D.new()
	host.name = "PoseHost"
	get_tree().root.add_child(host)

	var ids := Utils.weapon_list.keys()
	ids.sort()
	_check("WEAPON_TABLE_NOT_EMPTY", ids.size() >= 20, "found %d weapons" % ids.size())

	for id in ids:
		await _check_weapon_pose(host, str(id))

	host.queue_free()
	await _wait(0.1)

func _check_weapon_pose(host: Node2D, id: String) -> void:
	var packed: PackedScene = Utils.weapon_list[id]
	_check("W%s_SCENE" % id, packed != null)
	if packed == null: return
	var gun = packed.instantiate()
	host.add_child(gun)
	await get_tree().process_frame

	_check("W%s_ANCHOR_CAPTURED" % id, gun.pose_captured,
		"a gun must record its resting pose when it enters the tree")
	_check("W%s_ANCHOR_IS_SCENE_POSE" % id,
		gun.position.distance_to(gun.resting_position) <= DRIFT_EPSILON,
		"position=%s anchor=%s" % [str(gun.position), str(gun.resting_position)])

	var tip = gun.get_node_or_null("GunTip")
	_check("W%s_MUZZLE_EXISTS" % id, is_instance_valid(tip),
		"GunTip present=%s" % str(is_instance_valid(tip)))
	# The flash and the projectile must share one origin, or a shot appears to come
	# from somewhere the gun is not.
	var flash_ok: bool = is_instance_valid(gun.tier_muzzle) and tip != null and tip.is_ancestor_of(gun.tier_muzzle)
	_check("W%s_MUZZLE_OWNS_FLASH" % id, flash_ok,
		"tier_muzzle hangs off GunTip=%s" % str(flash_ok))

	# A single shot returns to the anchor...
	gun.play_shot_feedback(0.15)
	await _wait(0.35)
	_check("W%s_SINGLE_SHOT_RETURNS" % id,
		gun.position.distance_to(gun.resting_position) <= DRIFT_EPSILON,
		"position=%s anchor=%s" % [str(gun.position), str(gun.resting_position)])

	# ...and so does interrupting one mid-flight.
	gun.play_shot_feedback(5.0)
	var mid: float = gun.position.distance_to(gun.resting_position)
	_check("W%s_MID_ANIM_OFFSET_BOUNDED" % id, mid <= MAX_ANIM_OFFSET,
		"displacement=%.3f ceiling=%.1f" % [mid, MAX_ANIM_OFFSET])
	gun.restore_pose()
	_check("W%s_INTERRUPT_RESTORES" % id,
		gun.position.distance_to(gun.resting_position) <= DRIFT_EPSILON,
		"position=%s anchor=%s" % [str(gun.position), str(gun.resting_position)])

	# The regression itself: fire far faster than the animation resolves, the way
	# Baby does when it animates once per pellet. The old tween chain walked away
	# from the anchor here; the fixed one cannot, because every target is the anchor.
	var overshoot := 0.0
	for _i in RAPID_SHOTS:
		gun.play_shot_feedback(0.15)
		overshoot = maxf(overshoot, float(gun.position.distance_to(gun.resting_position)))
	await _wait(0.5)
	var drift: float = gun.position.distance_to(gun.resting_position)
	_check("W%s_RAPID_FIRE_NO_DRIFT" % id, drift <= DRIFT_EPSILON,
		"after %d rapid shots position=%s anchor=%s drift=%.4f" % [
			RAPID_SHOTS, str(gun.position), str(gun.resting_position), drift])
	_check("W%s_RAPID_FIRE_BOUNDED" % id, overshoot <= MAX_ANIM_OFFSET,
		"max displacement during rapid fire=%.3f ceiling=%.1f" % [overshoot, MAX_ANIM_OFFSET])

	gun.queue_free()
	await get_tree().process_frame

## ---------------------------------------------------------------- part 2 ----

func _part2_muzzle_origin() -> void:
	var main = load(MENU_SCENE).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _wait(0.6)

	var menu := _main_ui()
	if menu == null:
		_check("MUZZLE_MENU_PRESENT", false, "cannot start a session without the menu")
		return
	var start: Button = menu.get_node_or_null("VBoxContainer/start")
	if start == null:
		_check("MUZZLE_START_BUTTON", false, "start button missing")
		return
	start.pressed.emit()
	await _wait(0.6)
	if is_instance_valid(Demo.ui):
		var panel = Demo.ui
		Demo.pop_pause(panel)
		panel.queue_free()
		Demo.ui = null
	await _wait(0.2)

	var player = Utils.player
	_check("MUZZLE_PLAYER_PRESENT", is_instance_valid(player))
	if not is_instance_valid(player): return
	var gun_root = player.gun_root
	_check("MUZZLE_GUN_ROOT", is_instance_valid(gun_root))
	if not is_instance_valid(gun_root): return

	for id in MUZZLE_WEAPONS:
		await _check_muzzle_origin(player, gun_root, int(id))

	# A change card for a weapon the player does not own must be a no-op, not an
	# abort. This is the exact shape of the failure the muzzle loop used to trigger
	# before the HUD guarded its lookup, so it is pinned here on purpose: a script
	# error would end this coroutine before the check below is reached.
	var ui := _game_ui()
	if ui != null:
		ui.onWeaponChangeAnim(9999)
		await _wait(0.2)
		_check("UNOWNED_WEAPON_CARD_SAFE",
			is_instance_valid(ui) and ui.ammo_count_label.text != "",
			"the HUD must survive a change for an unowned weapon")
	else:
		_check("UNOWNED_WEAPON_CARD_SAFE", false, "GameUI missing")

func _check_muzzle_origin(player, gun_root, id: int) -> void:
	var packed: PackedScene = _scene_for(id)
	if packed == null:
		_check("MUZZLE_W%d_SCENE" % id, false, "no scene for weapon %d" % id)
		return
	var gun = packed.instantiate()
	gun_root.add_child(gun)
	await get_tree().process_frame
	gun.setOwner(player)
	# Equip it the way the game does. A gun becomes the player's only after it is
	# added to the arsenal, and the HUD reads the change card's name and icon from
	# that entry - so skipping this step tests a state the product never reaches.
	PlayerData.add_weapon(gun)
	# Freeze the projectiles so the spawn point can be read without predicting motion.
	gun.bullet_speed = 0.0
	gun.bullets_count = gun.bullets_max_count
	gun.set_use(true)
	await get_tree().process_frame

	var tip = gun.get_node_or_null("GunTip")
	var tip_position: Vector2 = tip.global_position if tip != null else Vector2.ZERO
	var pellets: int = gun.projectile_count()
	var before := _bullet_ids()

	gun.can_shoot = true
	gun._shoot()
	# Baby paces its pellets; give the slowest weapon room to finish.
	await _wait(0.8)

	var spawned := _new_bullets(before)
	_check("MUZZLE_W%d_SPAWN_COUNT" % id, spawned.size() == pellets,
		"spawned=%d expected=%d" % [spawned.size(), pellets])
	var worst: float = 0.0
	for bullet in spawned:
		if not is_instance_valid(bullet): continue
		worst = maxf(worst, float(bullet.global_position.distance_to(tip_position)))
	_check("MUZZLE_W%d_PROJECTILES_AT_MUZZLE" % id,
		spawned.size() == pellets and worst <= 1.0,
		"pellets=%d worst_distance_from_muzzle=%.3f" % [spawned.size(), worst])

	# Firing must not move the gun off its anchor either.
	_check("MUZZLE_W%d_POSE_HELD" % id,
		gun.position.distance_to(gun.resting_position) <= MAX_ANIM_OFFSET,
		"position=%s anchor=%s" % [str(gun.position), str(gun.resting_position)])

	for bullet in spawned:
		if is_instance_valid(bullet): bullet.queue_free()
	gun.set_use(false)
	PlayerData.player_weapon_list.erase(gun.weapon_id)
	gun.queue_free()
	await get_tree().process_frame

func _bullet_ids() -> Array:
	var ids: Array = []
	for child in get_tree().root.get_children():
		if child is Bullet: ids.append(child.get_instance_id())
	return ids

func _new_bullets(before: Array) -> Array:
	var found: Array = []
	for child in get_tree().root.get_children():
		if child is Bullet and not before.has(child.get_instance_id()):
			found.append(child)
	return found

func _main_ui() -> Node:
	if not is_instance_valid(Utils.canvasLayer): return null
	return Utils.canvasLayer.get_node_or_null("MainUI")

func _game_ui() -> Node:
	if not is_instance_valid(Utils.canvasLayer): return null
	return Utils.canvasLayer.get_node_or_null("GameUI")

## Looks a weapon scene up by numeric id without assuming the key type of
## Utils.weapon_list (its keys are Strings today; comparing numerically keeps this
## honest if that ever changes).
func _scene_for(id: int) -> PackedScene:
	for key in Utils.weapon_list:
		if int(str(key)) == id:
			return Utils.weapon_list[key]
	return null

func _finish() -> void:
	print("POSE_RESULT checks=%d failures=%d" % [_checks, _failures])
	if _failures > 0:
		print("POSE_RESULT=FAIL")
		get_tree().quit(1)
	else:
		print("POSE_RESULT=PASS")
		get_tree().quit(0)

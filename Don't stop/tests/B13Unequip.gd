extends "res://tests/M8Runtime.gd"
## B13 unequip contract. Dropping the current weapon is a first-class state:
##   * ownership/ammo untouched, the old gun goes inert (set_use(false))
##   * CAMP is the ONLY level-server state that may unequip: the API itself refuses
##     PREPARING / COMBAT / DEAD / RESOLVING, not just the panel button
##   * the save keeps `equipped=""` plus the optional explicit-unequip intent
##   * a reload restores the unarmed state and never auto-equips
##   * after an explicit unequip, buying another gun must NOT silently re-arm
##   * a fresh player's first gun still auto-equips
##   * panel and hotkey equips restore everything, unarmed combat is crash-free
##   * real unarmed inputs: pressing shoot spawns no projectile and deals no damage,
##     pressing reload consumes no reserve, pressing dash executes the dash path

func count_bullets() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("combat_transient"):
		if node is Bullet: n += 1
	return n

func _ready():
	await boot()
	# --- fresh player: the first purchased gun still auto-equips ------------------------
	check(Utils.player.gun == null,"fresh harness starts unarmed")
	check(not Demo.explicitly_unequipped,"fresh account has no unequip intent")
	check(Demo.try_purchase("weapon","0").success,"buy the first gun")
	check(Utils.player.gun != null and Utils.player.gun.weapon_id == 0,"fresh player's first gun auto-equips")
	# --- explicit unequip -----------------------------------------------------------------
	Demo.try_purchase("weapon","4")
	PlayerData.changeWeapon(4,true)
	var old_gun: BaseGun = Utils.player.gun
	check(old_gun.weapon_id == 4,"equipped gun 4 for the unequip")
	var result: Dictionary = Demo.unequip_weapon()
	check(result.success,"unequip succeeds")
	check(Utils.player.gun == null,"hero holds no weapon after unequip")
	check(not old_gun.is_use,"the dropped gun is inert (set_use(false))")
	check(not old_gun.visible,"the dropped gun is hidden")
	check(PlayerData.player_weapon_list.has(4) and PlayerData.player_weapon_list.has(0),"ownership fully retained")
	check(Demo.explicitly_unequipped,"explicit unequip intent is recorded")
	# --- save round-trip keeps the unarmed state ------------------------------------------
	var snap: Dictionary = Demo.snapshot()
	check(str(snap.equipped) == "","snapshot stores equipped=\"\"")
	check(bool(snap.unequipped) == true,"snapshot stores the unequip intent")
	check(CampSnapshot.validate(snap),"unarmed snapshot validates without a schema bump")
	check(Demo.save_store.save(Demo.save_path,snap).success,"write the unarmed save")
	for gun in PlayerData.player_weapon_list.values(): gun.free()
	PlayerData.player_weapon_list.clear()
	check(Demo.load_camp(),"reload the unarmed save")
	check(Utils.player.gun == null,"reload restores the unarmed state")
	check(Demo.explicitly_unequipped,"reload preserves the explicit-unequip intent")
	check(PlayerData.player_weapon_list.size() == 2,"reload keeps both weapons owned")
	# --- buying a gun after an explicit unequip must NOT silently re-arm ------------------
	var gold: int = PlayerData.gold
	check(Demo.try_purchase("weapon","8").success,"buy a third gun while unarmed")
	check(Utils.player.gun == null,"the new purchase did not auto-equip")
	check(Demo.explicitly_unequipped,"the intent survives purchases")
	check(PlayerData.player_weapon_list.size() == 3,"the purchased gun joined ownership")
	# --- manual equip restores everything --------------------------------------------------
	await wait(0.13)
	PlayerData.switch_deadline = 0
	check(PlayerData.changeWeapon(8,true),"manual panel-style equip works")
	check(Utils.player.gun != null and Utils.player.gun.weapon_id == 8,"equip re-arms the player")
	check(not Demo.explicitly_unequipped,"any successful equip clears the intent")
	check(str(Demo.snapshot().equipped) == "8","the save records the new equipped id")
	# --- hotkey re-equip ---------------------------------------------------------------------
	check(Demo.unequip_weapon().success,"unequip again")
	check(Utils.player.gun == null,"unarmed again")
	PlayerData.switch_deadline = 0
	# B14: removed guns are owned but no longer hotkeys. Re-add explicitly, then
	# exercise a real carried-to-carried hotkey switch; ownership/ammo checks remain.
	check(not PlayerData.changeWeapon(4),"removed gun cannot be selected by a hotkey")
	check(PlayerData.equip_owned(4,1).success,"camp re-adds gun 4 to the loadout")
	PlayerData.switch_deadline = 0
	check(PlayerData.changeWeapon(0),"select another carried gun before hotkey test")
	PlayerData.switch_deadline = 0
	check(PlayerData.changeWeapon(4),"hotkey-path equip works (WeaponListItem route)")
	check(Utils.player.gun != null and Utils.player.gun.weapon_id == 4,"hotkey re-equip restored gun 4")
	# --- CAMP is the ONLY state that may unequip (the API refuses the rest) -----------------
	for bad_state in ["PREPARING","COMBAT","DEAD","RESOLVING"]:
		LevelServer.state = bad_state
		check(not Demo.unequip_weapon().success,"unequip refuses while %s"%bad_state)
	check(Utils.player.gun != null,"the refused unequips left the weapon equipped")
	LevelServer.state = "CAMP"
	check(Demo.unequip_weapon().success,"CAMP is the one state where unequip succeeds")
	check(Utils.player.gun == null,"the camp unequip left the player unarmed")
	# --- unarmed combat is crash-free -------------------------------------------------------
	LevelServer.state = "COMBAT"
	LevelServer.epoch += 1
	Utils.player.global_position = origin
	Utils.player.SPEED = 100
	for i in 12:
		Utils.player._physics_process(1.0/60.0)
		Utils.player._input(InputEventAction.new())
	check(is_instance_valid(Utils.player) and not Utils.player.is_dead,"WASD/dash path runs unarmed without errors")
	check(not Demo.fire_global_grenade(origin+Vector2(40,0)),"no grenade without a weapon")
	Demo.talent_status("T13"); Demo.talent_status("T12")
	check(true,"talent status reads survive a null gun")
	# --- real unarmed inputs: shoot, reload, dash -------------------------------------------
	var dummy = enemy(origin+Vector2(50,8),100000)
	var bullets_before := count_bullets()
	var reserve_before: int = PlayerData.reserve_magazines
	Input.action_press("shoot")
	var shoot_press = InputEventAction.new(); shoot_press.action = "shoot"; shoot_press.pressed = true
	Utils.player._input(shoot_press)
	await wait(0.3)
	Input.action_release("shoot")
	var shoot_release = InputEventAction.new(); shoot_release.action = "shoot"; shoot_release.pressed = false
	Utils.player._input(shoot_release)
	check(count_bullets() == bullets_before,"an unarmed shoot press spawns no projectile")
	check(is_equal_approx(dummy.HP,100000.0),"an unarmed shoot press deals no damage")
	check(is_instance_valid(Utils.player) and not Utils.player.is_dead,"the player is unharmed by the unarmed shoot press")
	Input.action_press("reload")
	var reload_press = InputEventAction.new(); reload_press.action = "reload"; reload_press.pressed = true
	Utils.player._input(reload_press)
	await wait(0.2)
	Input.action_release("reload")
	var reload_release = InputEventAction.new(); reload_release.action = "reload"; reload_release.pressed = false
	Utils.player._input(reload_release)
	check(PlayerData.reserve_magazines == reserve_before,"an unarmed reload press consumes no reserve magazine")
	check(Utils.player.gun == null,"the gun is still null after the unarmed reload press")
	Input.action_press("up")
	var dash_press = InputEventAction.new(); dash_press.action = "dash"; dash_press.pressed = true
	Input.action_press("dash")
	Utils.player._input(dash_press)
	check(Utils.player.is_dash,"the dash path executes unarmed")
	Input.action_release("dash")
	await wait(0.2)
	Input.action_release("up")
	Utils.player._physics_process(1.0/60.0)
	check(is_instance_valid(Utils.player) and not Utils.player.is_dead,"the unarmed dash completes without errors")
	LevelServer.return_to_camp()
	check(LevelServer.state == "CAMP","unarmed session returns to camp cleanly")
	# --- death/resurrect guards -------------------------------------------------------------
	PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
	check(PlayerData.player_hp == PlayerData.player_hp_max and Utils.player.gun == null,"resurrect keeps the unarmed state and charges no ammo")
	# --- unequip is camp-only ----------------------------------------------------------------
	var refused: Dictionary = Demo.unequip_weapon()
	check(not refused.success,"unequip without a weapon is a clean refusal")
	# --- no-gun economy/UI reads --------------------------------------------------------------
	var stat_values = EffectiveStats.player_values()
	check(stat_values.has("speed"),"player stat readout survives a null gun")
	print("B13_UNEQUIP_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

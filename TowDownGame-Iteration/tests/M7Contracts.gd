extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true; seed(707)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); await wait(0.3)
	check(PlayerData.gold == DemoConfig.INITIAL_GOLD and PlayerData.reward_point == 0,"normal fresh wallet is modest")
	PlayerData.gold = 100000
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	for gun in PlayerData.player_weapon_list.values():
		aim(gun)
		for old in gun.attachments_dict.values().duplicate(): gun.removeAttachMent(old)
		var before = gun.effective.duplicate(true)
		for id in Utils.am_dict:
			var am = Utils.am_dict[id].instantiate(); am.id = Demo.next_instance; Demo.next_instance += 1; PlayerData.add_attachment(am)
			check(am.can_equip(gun) and gun.addAttachMent(am),"universal install %s/%s" % [id,gun.weapon_id])
			check(gun.effective != before,"universal effective benefit %s/%s" % [id,gun.weapon_id])
			check(Demo.valid_save(Demo.snapshot()),"universal saved graph %s/%s" % [id,gun.weapon_id])
			gun.removeAttachMent(am); PlayerData.player_am_list.erase(am.id); am.queue_free()
		PlayerData.reserve_magazines = 10
		for cycle in 10:
			gun.bullets_count = 0
			gun.reload_ammo()
			await wait(gun.effective.reload+0.03)
			check(gun.bullets_count == gun.bullets_max_count and PlayerData.reserve_magazines == 9-cycle,"timed reload %s/%s" % [gun.weapon_id,cycle])
		gun.bullets_count = 0; gun.reload_ammo(); await wait(0.02)
		check(not gun.is_reloading and gun.bullets_count == 0,"no reserve cannot reload %s" % gun.weapon_id)
		PlayerData.reserve_magazines = 2; gun.reload_ammo(); gun.cancel_actions()
		check(PlayerData.reserve_magazines == 2,"cancel does not spend magazine")
	print("M7 CONTRACT SUMMARY checks=",checks," failures=",failures)
	await Demo.quit_game()

extends Node

var failures = 0
func check(ok: bool, label: String):
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _ready():
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	PlayerData.player_exp = PlayerData.getMaxExp()
	check(PlayerData.player_level == 2, "A01 exact threshold upgrades immediately")
	var gun = Utils.weapon_list["0"].instantiate()
	PlayerData.add_weapon(gun)
	var magazine = gun.bullets_max_count
	PlayerData.base_magazine_count = 0.1
	gun.updateGun()
	var first = gun.bullets_max_count
	for i in 20: gun.updateGun()
	check(gun.bullets_max_count == first, "A05 refresh does not multiply capacity")
	PlayerData.base_magazine_count = 0
	gun.updateGun()
	check(gun.bullets_max_count == magazine, "A05 remove restores base capacity")
	var shop = load("res://ui/widgets/ShopPanel.tscn").instantiate()
	add_child(shop)
	var am = Utils.am_dict["0"].instantiate()
	shop.onAmClick("0", am)
	shop.onWeaponClick("0", gun)
	check(shop.choose_am == null, "A02 weapon selection clears attachment")
	am.free()
	print("BASELINE REGRESSION failures=", failures)
	main.get_node("AudioStreamPlayer").stop()
	await get_tree().create_timer(0.1,true).timeout
	get_tree().quit(1 if failures else 0)

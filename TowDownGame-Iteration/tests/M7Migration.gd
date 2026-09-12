extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 10000
	Demo.try_purchase("weapon","0")
	for count in 2: Demo.try_purchase("attachment","122")
	Utils.player.changeWeapon(0)
	var old = Demo.snapshot(); old.schema_version = 4; old.ammo = 251; old.erase("reserve_magazines")
	old.equipped = "0"; old.weapons[0].ammo = 25
	old.compatibility = {"122":["chain"]}
	Demo.save_path = "res://evidence/m7-migration.json"
	check(Demo.valid_save(old),"schema4 exact historical bullet reserve valid")
	check(Demo.save_store.save(Demo.save_path,old).success and Demo.load_camp(),"schema4 actual disk migration")
	check(PlayerData.reserve_magazines == 11,"251 old rounds / original25 capacity rounds up once to11")
	var gold = PlayerData.gold; var instances = PlayerData.player_am_list.keys()
	check(Utils.player.gun.addAttachMent(PlayerData.player_am_list[instances[0]]),"formerly chain-only attachment equips old ordinary gun")
	for count in 5:
		var snap = Demo.snapshot()
		check(snap.schema_version == 5 and not snap.has("ammo") and snap.reserve_magazines == 11,"new schema stores magazines only")
		check(Demo.save_store.save(Demo.save_path,snap).success and Demo.load_camp(),"repeated actual current restore")
		check(PlayerData.gold == gold and PlayerData.player_am_list.keys() == instances and PlayerData.reserve_magazines == 11,"migration no currency instance or magazine duplication")
	var current = Demo.snapshot()
	for bad in [-1,0.5,"ten",null]:
		var invalid = current.duplicate(true); invalid.reserve_magazines = bad
		check(not Demo.valid_save(invalid),"invalid reserve count rejected "+str(bad))
	var missing = current.duplicate(true); missing.erase("reserve_magazines"); missing.ammo = 100000
	check(not Demo.valid_save(missing),"schema5 cannot fall back to obsolete bullet reserve")
	var gun = Utils.player.gun; aim(gun); PlayerData.reserve_magazines = 2; gun.bullets_count = gun.bullets_max_count-1
	gun.reload_ammo(); await wait(gun.effective.reload+0.05)
	check(PlayerData.reserve_magazines == 1 and gun.bullets_count == gun.bullets_max_count,"manual partial reload spends exactly one whole magazine")
	gun.reload_ammo(); await wait(0.05)
	check(PlayerData.reserve_magazines == 1,"full magazine reload does not spend")
	print("M7 MIGRATION SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

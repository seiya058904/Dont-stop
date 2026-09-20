extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(122)
	Demo.save_path="user://b15-saw-save-isolated.json"
	Demo.talents={}; Demo.owned_global_upgrades=[]; Demo.refresh()
	Utils.player.gun.updateGun()
	for rounds in [12,24]:
		Utils.player.gun.bullets_count=rounds
		var snapshot=Demo.snapshot()
		check(CampSnapshot.validate(snapshot),"old/new saw capacity validates %d"%rounds)
		check(Demo.save_store.save(Demo.save_path,snapshot).success and Demo.load_camp(),"old/new saw file reloads %d"%rounds)
		check(Utils.player.gun.bullets_count==rounds,"reload preserves exact saw ammunition %d"%rounds)
	var invalid=Demo.snapshot()
	for weapon in invalid.weapons:
		if weapon.id=="122": weapon.ammo=25
	check(not CampSnapshot.validate(invalid),"bare saw over-capacity save remains rejected")
	print("B15 SAVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

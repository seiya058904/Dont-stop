extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true
	Demo.save_path = "user://m4-persistence-test.json"
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.2)
	if "read" in OS.get_cmdline_user_args():
		check(Demo.load_camp(),"cross-process schema3 restore")
		check(PlayerData.player_weapon_list.size() == 24 and Demo.talents.size() == 24,"cross-process all weapons and talents")
		check(PlayerData.player_am_list.size() == 4,"cross-process four magazine instances")
		check(PlayerData.player_weapon_list[0].bullets_count == 4 and PlayerData.player_weapon_list[4].bullets_count == 7,"cross-process expanded magazines preserve exact ammo")
		var refund = Demo.reset_preview()
		check(refund.gold == 2400 and refund.points == 0 and refund.unknown == 0,"cross-process exact payment ledger")
		var old_gold = PlayerData.gold
		check(Demo.reset_talents(refund.revision).success and PlayerData.gold == old_gold+2400,"cross-process refund actual gold")
		check(not Demo.reset_talents(refund.revision).success and PlayerData.gold == old_gold+2400,"cross-process repeat click cannot refund again")
	else:
		for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
		for id in DemoConfig.TALENTS: Demo.try_purchase("talent",id,"gold")
		for id in [0,4]:
			for definition in ["1","2"]:
				var result = Demo.try_purchase("attachment",definition)
				PlayerData.player_weapon_list[id].addAttachMent(PlayerData.player_am_list[result.instance_id])
		PlayerData.player_weapon_list[0].bullets_count = 4
		PlayerData.player_weapon_list[4].bullets_count = 7
		var data = Demo.snapshot()
		check(Demo.valid_save(data),"schema3 with all talents valid")
		check(Demo.save_store.save(Demo.save_path,data).success,"write independent cross-process fixture")
		for version in [1,2]:
			var old = data.duplicate(true)
			old.schema_version = version
			old.erase("talent_payments")
			check(Demo.valid_save(old),"old version accepted without fabricated history "+str(version))
			check(Demo.save_store.save(Demo.save_path+"-old",old).success,"write old version fixture")
			var actual_path = Demo.save_path
			Demo.save_path += "-old"
			check(Demo.load_camp(),"old version actual restore "+str(version))
			var preview = Demo.reset_preview()
			check(preview.unknown == 24 and preview.gold == 0 and preview.points == 0 and Demo.talents.size() == 24,"old ranks retained, unknown payment explicit")
			Demo.save_path = actual_path
		check(Demo.load_camp(),"restore current fixture after migration tests")
		for round in 3:
			check(Demo.save_store.save(Demo.save_path,Demo.snapshot()).success and Demo.load_camp(),"repeat restore no duplicate source "+str(round))
			check(PlayerData.player_am_list.size() == 4 and PlayerData.player_weapon_list[0].bullets_count == 4 and PlayerData.player_weapon_list[4].bullets_count == 7,"instance and expanded ammo stable "+str(round))
		for mode in ["missing","duplicate","currency","amount","level","fractional_schema"]:
			var bad = data.duplicate(true)
			match mode:
				"missing": bad.erase("talent_payments")
				"duplicate": bad.talent_payments.append(bad.talent_payments[0].duplicate())
				"currency": bad.talent_payments[0].currency = "guessed"
				"amount": bad.talent_payments[0].amount = -1
				"level": bad.talent_payments[0].level = 9
				"fractional_schema": bad.schema_version = 3.5
			check(not Demo.valid_save(bad),"bad payment schema rejected "+mode)
	await wait(0.5)
	print("M4 PERSISTENCE SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

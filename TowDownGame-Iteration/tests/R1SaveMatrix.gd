extends Node
var failures = 0
func check(ok, name):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	for frame in 8: await get_tree().physics_frame
	var args = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-save")
	if args[0] == "write":
		Demo.try_purchase("weapon","0")
		Demo.try_purchase("weapon","4")
		Demo.try_purchase("talent","T04","points")
		var optics = []
		var magazines = []
		for id in [0,4]: optics.append(Demo.try_purchase("attachment","110").instance_id)
		for id in [0,4]: magazines.append(Demo.try_purchase("attachment","1").instance_id)
		for i in 2:
			var gun = PlayerData.player_weapon_list[[0,4][i]]
			gun.addAttachMent(PlayerData.player_am_list[optics[i]])
			gun.addAttachMent(PlayerData.player_am_list[magazines[i]])
		for variation in 3:
			for i in 2:
				var gun = PlayerData.player_weapon_list[[0,4][i]]
				gun.bullets_count = int(gun.bullets_max_count * [1.0,0.0,0.5][(variation+i)%3])
			PlayerData.reserve_magazines = 123+variation
			Demo.save_path = "res://evidence/r1-save/case-%d.json" % variation
			Demo.test_mode = false
			Demo.save_camp()
			Demo.test_mode = true
			var file = FileAccess.open("res://evidence/r1-save/expected-%d.json" % variation,FileAccess.WRITE)
			file.store_string(JSON.stringify(Demo.snapshot()))
			file.close()
	else:
		var variation = int(args[1])
		Demo.save_path = "res://evidence/r1-save/case-%d.json" % variation
		if "reverse" in args:
			var data = JSON.parse_string(FileAccess.get_file_as_string(Demo.save_path))
			data.attachments.reverse()
			var file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
			file.store_string(JSON.stringify(data)); file.close()
		Demo.load_camp()
		var expected = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/r1-save/expected-%d.json" % variation))
		for w in expected.weapons:
			check(PlayerData.player_weapon_list[int(w.id)].bullets_count == w.ammo,"R02 exact ammo gun "+w.id+" case "+str(variation))
		check(PlayerData.reserve_magazines == expected.reserve_magazines,"R02 exact reserve")
		check(PlayerData.player_am_list.size() == 4,"R02 duplicate model instances remain distinct")
		Demo.test_mode = false
		Demo.save_camp()
		Demo.test_mode = true
	print("R1 SAVE failures=",failures)
	for kind in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for node in get_tree().root.find_children("*",kind,true,false): node.stream_paused = false; node.stop()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit(1 if failures else 0)

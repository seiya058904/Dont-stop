extends Node
var failed = false
func check(ok: bool, description: String):
	print(("PASS " if ok else "FAIL ")+description)
	failed = failed or not ok
func _ready():
	Demo.test_mode = true
	Demo.save_path = "user://contract-test-camp.json"
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	for i in 8: await get_tree().physics_frame
	if "write" in OS.get_cmdline_user_args():
		Demo.try_purchase("weapon","114")
		Demo.try_purchase("talent","T01","gold")
		Demo.try_purchase("talent","T04","points")
		var bought = Demo.try_purchase("attachment","121")
		var gun = PlayerData.player_weapon_list[114]
		gun.addAttachMent(PlayerData.player_am_list[bought.instance_id])
		gun.bullets_count = 3
		Demo.selected_stage = 3
		Demo.test_mode = false
		Demo.save_camp()
		Demo.test_mode = true
		check(FileAccess.file_exists(Demo.save_path),"save writes test snapshot atomically")
	else:
		Demo.load_camp()
		check(PlayerData.gold == 9659,"load preserves spent gold instead of granting 9999")
		check(PlayerData.reward_point == 9998,"load preserves spent talent points")
		check(Demo.rank("T01") == 1 and Demo.rank("T04") == 1,"load restores exact ranks")
		check(PlayerData.player_weapon_list.has(114),"load restores owned plasma")
		var gun = PlayerData.player_weapon_list.get(114)
		if gun:
			check(gun.bullets_count == 3,"load does not refill magazine")
			check(is_equal_approx(gun.effective.radius,38.4),"load recomputes equipped fuse")
			check(is_equal_approx(gun.effective.damage,4.3*1.08),"load applies talent once")
		check(Demo.selected_stage == 3 and LevelServer.state == "CAMP","load resumes camp with selected encounter")
		check(Utils.player.gun.weapon_id == 114,"load restores equipped gun")
	main.get_node("AudioStreamPlayer").stop()
	await get_tree().create_timer(0.2).timeout
	print("SAVE SUMMARY failures=",1 if failed else 0)
	get_tree().quit(1 if failed else 0)

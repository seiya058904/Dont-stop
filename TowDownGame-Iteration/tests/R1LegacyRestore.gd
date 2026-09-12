extends Node
var failures = 0
func check(ok,name):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func _ready():
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	for i in 8: await get_tree().physics_frame
	Demo.try_purchase("weapon","0")
	for id in ["2","5","8"]: Demo.try_purchase("legacy",id)
	var hp = PlayerData.player_hp_max
	var speed = Utils.player.SPEED
	var data = Demo.snapshot().duplicate(true)
	check(Demo.valid_save(data) and hp == PlayerData.player_hp_max and speed == Utils.player.SPEED,"R03 validation previews have no reward side effects")
	var sickle = Utils.player.reward_root.get_node("REWARD AMBER SICKLE")
	var baseline_rate = PlayerData.player_fire_rate
	sickle.doBuff()
	check(is_equal_approx(PlayerData.player_fire_rate,baseline_rate+0.2),"legacy actual temporary buff active")
	Demo.save_path = "res://evidence/r1-save/legacy-restore.json"
	Demo.test_mode = false; Demo.save_camp(); Demo.test_mode = true
	check(Demo.load_camp(),"legacy load during temporary buff")
	check(is_equal_approx(PlayerData.player_fire_rate,baseline_rate),"legacy discarded reward instance removes only its temporary rate buff")
	check(hp == PlayerData.player_hp_max and speed == Utils.player.SPEED,"legacy health and movement permanent rewards apply once")
	print("LEGACY RESTORE failures=",failures)
	await Demo.quit_game()

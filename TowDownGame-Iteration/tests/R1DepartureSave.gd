extends Node
var failed = false
func check(ok,name):
	if not ok: failed = true
	print(("PASS " if ok else "FAIL ")+name)
func _ready():
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	for i in 8: await get_tree().physics_frame
	var args = OS.get_cmdline_user_args()
	Demo.save_path = "res://evidence/r1-save/departure-"+args[1]+".json"
	if args[0] == "write":
		Demo.try_purchase("weapon","0")
		LevelServer.town.depart(1,false); LevelServer.victory()
		for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
		if args[1] == "trial":
			LevelServer.town.depart(4,true); LevelServer.victory()
			for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
		Demo.test_mode = false
		check(Demo.save_camp().success,"R05 write "+args[1]+" camp")
		Demo.test_mode = true
	else:
		check(Demo.load_camp(),"R05 restore in fresh process "+args[1])
		var epoch = LevelServer.epoch
		LevelServer.town._on_portal_move_in(LevelServer.town.portal_lv1)
		LevelServer.town._on_portal_2_move_out()

		# M5 fills the previously unavailable stage 2; normal progression no longer skips it.
		check(LevelServer.level == 2 and not Demo.trial and LevelServer.epoch == epoch+1,"R05 fresh process old gate starts next normal encounter "+args[1])
	print("DEPARTURE SAVE failures=",int(failed))
	await Demo.quit_game()

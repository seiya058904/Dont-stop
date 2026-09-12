extends Node
class FaultStore extends CampSaveStore:
	func open_temp(_path): return null
var checks = 0
var failures = 0
func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func frames():
	for frame in 5: await get_tree().process_frame
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-recovery")
	Demo.save_path = "res://evidence/r1-recovery/bad.json"
	var raw = '{"legacy":'
	var file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
	file.store_string(raw); file.close()
	add_child(load("res://game/map/Main.tscn").instantiate())
	# The real start button calls these synchronously in this order.
	Utils.gameStart(); Demo.open_panel()
	await frames()
	check(Demo.pause_stack.back() == Demo.save_dialog and Demo.save_dialog.get_index() > Demo.ui.get_index(),"R03 recovery dialog stays above startup camp panel")
	check(FileAccess.get_file_as_string(Demo.save_path) == raw,"R03 startup keeps corrupt bytes")
	Demo.quit_game(); await frames()
	check(Demo.save_dialog.quitting,"R04 existing recovery prompt gains quit choices")
	var cancel = Demo.save_dialog.find_children("*","Button",true,false).filter(func(b): return b.text == "取消退出")
	check(cancel.size() == 1,"R04 cancel quit remains available")
	if not cancel.is_empty(): cancel[0].pressed.emit()
	else: Demo.save_dialog.queue_free()
	await frames()
	Demo.try_purchase("weapon","0")
	check(Demo.dirty and FileAccess.get_file_as_string(Demo.save_path) == raw,"R03 temporary purchase cannot overwrite bad file")
	check(Demo.create_new_save(),"R03 explicit fresh profile backs up and takes over")
	Demo.save_store = FaultStore.new()
	var purchase = Demo.try_purchase("weapon","0")
	Demo.quit_game(); await frames()
	check(purchase.success and not purchase.saved and Demo.save_dialog.quitting,"R04 open failure keeps purchased state and blocks exit")
	var gold = PlayerData.gold
	Demo.save_dialog.find_children("*","Button",true,false).filter(func(b): return b.text == "取消退出")[0].pressed.emit()
	await frames()
	check(not is_instance_valid(Demo.save_dialog) and PlayerData.gold == gold and Demo.dirty,"R04 cancel exit preserves unsaved purchase")
	Demo.save_store = CampSaveStore.new()
	check(Demo.save_camp().success and PlayerData.gold == gold,"R04 retry persists without another charge")
	print("R1 RECOVERY UI checks=",checks," failures=",failures)
	await Demo.quit_game()

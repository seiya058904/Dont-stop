extends Node
class FaultStore extends CampSaveStore:
	var fault = ""
	func open_temp(path):
		return null if fault == "open" else super.open_temp(path)
	func write_temp(file, text):
		if fault == "write":
			file.store_string(text.left(8)); file.flush()
			return ERR_FILE_CANT_WRITE
		return super.write_temp(file,text)
	func replace_file(source, destination):
		if fault == "replace": return ERR_CANT_CREATE
		var result = super.replace_file(source,destination)
		if fault == "readback" and result == OK:
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt-after-replace"); file.close()
		return result
var failures = 0
var checks = 0
func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func _ready():
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	for frame in 8: await get_tree().physics_frame
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-save")
	Demo.save_path = "res://evidence/r1-save/fault.json"
	Demo.try_purchase("weapon","0")
	Demo.try_purchase("legacy","10")
	var bacteria = Utils.player.reward_root.get_node("REWARD BLUE BACTERIA")
	bacteria.kill_count = 1000
	PlayerData.player_hp_max += 100
	var data = Demo.snapshot()
	var store = FaultStore.new()
	Demo.save_store = store
	Demo.test_mode = false
	check(Demo.save_camp().success,"R04 initial snapshot written")
	var previous = FileAccess.get_file_as_string(Demo.save_path)
	for fault in ["open","write","replace","readback"]:
		store.fault = fault
		var before = PlayerData.gold
		var count = PlayerData.player_am_list.size()
		var purchase = Demo.try_purchase("attachment","110")
		check(purchase.success and not purchase.saved and Demo.dirty,"R04 transaction succeeds but saving "+fault+" fails visibly")
		check(FileAccess.get_file_as_string(Demo.save_path) == previous,"R04 prior snapshot byte-identical after "+fault)
		check(PlayerData.gold == before-purchase.charged_amount and PlayerData.player_am_list.size() == count+1,"R04 charged once "+fault)
		store.fault = ""
		check(Demo.save_camp().success and not Demo.dirty,"R04 retry saves "+fault)
		check(PlayerData.gold == before-purchase.charged_amount and PlayerData.player_am_list.size() == count+1,"R04 retry never charges or grants again")
		previous = FileAccess.get_file_as_string(Demo.save_path)
		var expected = Demo.snapshot().duplicate(true)
		var loaded = Demo.load_camp()
		check(loaded and Demo.snapshot().weapons == expected.weapons and PlayerData.gold == expected.gold,"R04 written content actually restores")
	Demo.test_mode = true
	check(Utils.player.reward_root.get_node("REWARD BLUE BACTERIA").kill_count == 1000,"legacy bacteria lifetime cap survives load")
	var old = data.duplicate(true)
	old = M7Fixtures.legacy(old,1); old.erase("legacy_state")
	check(CampSnapshot.normalize(old).legacy_state["10"] == 1000,"v1 bacteria cap migrates from persisted HP")
	var cases = []
	var malformed = data.duplicate(true)
	malformed.attachments = [{"definition":"unknown","instance":1,"gun":"0"}]; malformed.next_instance = 2; cases.append(malformed)
	malformed = data.duplicate(true); malformed.weapons[0].ammo = 1.5; cases.append(malformed)
	malformed = data.duplicate(true); malformed.exp = PlayerData.getMaxExp(); cases.append(malformed)
	malformed = data.duplicate(true); malformed.hp = malformed.hp_max+1; cases.append(malformed)
	malformed = data.duplicate(true); malformed.legacy_state["10"] = 1001; cases.append(malformed)
	malformed = data.duplicate(true)
	malformed.attachments = [{"definition":"122","instance":1,"gun":"missing"}]; malformed.next_instance = 2; cases.append(malformed)
	for value in [{},[null]]:
		var bad = data.duplicate(true); bad.legacy = value; cases.append(bad)
	var bad = data.duplicate(true); bad.weapons[0].id = "missing"; cases.append(bad)
	bad = data.duplicate(true); bad.talents.T04 = -1; cases.append(bad)
	for broken in cases:
		var file = FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(broken)); file.close()
		var raw = FileAccess.get_file_as_string(Demo.save_path)
		var memory = JSON.stringify(Demo.snapshot())
		check(not Demo.load_camp() and JSON.stringify(Demo.snapshot()) == memory,"R03 invalid data never changes memory")
		Demo.test_mode = false
		check(not Demo.save_camp().success and FileAccess.get_file_as_string(Demo.save_path) == raw,"R03 temporary game cannot overwrite bad file")
		Demo.test_mode = true
	var file = FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string('{"level":'); file.close()
	check(not Demo.load_camp(),"R03 truncated JSON rejected")
	var raw = FileAccess.get_file_as_string(Demo.save_path)
	var exported = Demo.export_bad_save()
	check(FileAccess.get_file_as_string(exported) == raw,"R03 export preserves bad original bytes")
	old = data.duplicate(true); old = M7Fixtures.legacy(old,1); old.erase("legacy"); old.erase("legacy_state")
	check(Demo.valid_save(old),"R03 legal missing-legacy v1")
	data.legacy.append("0"); data.legacy.append("1"); data.hp = 0
	file = FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(Demo.load_camp() and PlayerData.gold == data.gold and PlayerData.player_hp == 0,"R03 old one-shot rewards neither regrant nor revive")
	print("R1 PERSISTENCE checks=",checks," failures=",failures)
	Demo.stop_attacks()
	await get_tree().create_timer(0.2,true).timeout
	get_tree().quit(1 if failures else 0)

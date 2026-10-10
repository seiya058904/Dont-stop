extends Node
class FaultStore extends CampSaveStore:
	var fault = ""
	var reject_rollback = false
	func open_temp(path):
		return null if fault == "open" else super.open_temp(path)
	func write_temp(file, text):
		if fault == "write":
			file.store_string(text.left(8)); file.flush()
			return ERR_FILE_CANT_WRITE
		if fault == "bom_temp":
			file.store_buffer(PackedByteArray([239,187,191]))
			file.store_string(text); file.flush()
			return file.get_error()
		return super.write_temp(file,text)
	func replace_file(source, destination):
		if fault == "replace": return ERR_CANT_CREATE
		var result = super.replace_file(source,destination)
		if fault == "readback" and result == OK:
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt-after-replace"); file.close()
		if fault == "bom_main" and result == OK:
			var bytes = FileAccess.get_file_as_bytes(destination)
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_buffer(PackedByteArray([239,187,191]))
			file.store_buffer(bytes); file.close()
		return result
	func restore_previous(previous_path, temporary, path, text):
		if reject_rollback: return false
		return super.restore_previous(previous_path,temporary,path,text)
var failures = 0
var checks = 0
func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)

func check_backup_retries(data: Dictionary):
	# Separate files/store leave the existing purchase and migration sequence
	# untouched. Fault both the replacement readback and its subsequent rollback.
	var path = "res://evidence/r1-save/backup-retry.json"
	var store = FaultStore.new()
	check(store.save(path,data).success,"R04 backup retry has a real prior snapshot")
	var original = FileAccess.get_file_as_bytes(path)
	var updated = data.duplicate(true)
	updated.gold -= 1
	store.fault = "readback"
	store.reject_rollback = true
	check(not store.save(path,updated).success,"R04 readback and rollback double failure is visible")
	check(FileAccess.get_file_as_bytes(path+".previous") == original,"R04 failed rollback retains the exact good predecessor")
	for attempt in 2:
		check(not store.save(path,updated).success,"R04 repeated double failure cannot succeed "+str(attempt))
		check(FileAccess.get_file_as_bytes(path+".previous") == original,"R04 retry never rotates corrupt main over good previous "+str(attempt))
	store.reject_rollback = false
	store.fault = ""
	check(store.save(path,updated).success,"R04 double-fault retry succeeds after storage recovers")
	check(FileAccess.get_file_as_bytes(path) == JSON.stringify(updated,"\t").to_utf8_buffer(),"R04 recovered retry writes exactly the intended snapshot")
	check(FileAccess.get_file_as_bytes(path+".previous") == original,"R04 recovered retry retains the last good predecessor")
	var updated_bytes = FileAccess.get_file_as_bytes(path)
	var following = updated.duplicate(true)
	following.gold -= 1
	check(store.save(path,following).success and FileAccess.get_file_as_bytes(path+".previous") == updated_bytes,"R04 ordinary backup rotation resumes after recovery")
	# The store also protects originals that cannot safely be decoded as UTF-8.
	# Byte arrays are compared directly; known malformed bytes are never passed
	# to JSON.parse_string merely to provoke a parser diagnostic.
	path = "res://evidence/r1-save/binary-retry.json"
	var raw = PackedByteArray([123,34,120,34,58,255,0,192,175,13,10])
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(raw); file.close()
	store.fault = "readback"
	check(not store.save(path,data).success and FileAccess.get_file_as_bytes(path) == raw,"R04 rollback restores invalid UTF-8 and NUL exactly")
	check(FileAccess.get_file_as_bytes(path+".previous") == raw,"R04 binary previous remains byte-identical")
	store.reject_rollback = true
	check(not store.save(path,data).success,"R04 binary original rollback failure is visible")
	check(not store.save(path,data).success and FileAccess.get_file_as_bytes(path+".previous") == raw,"R04 binary original survives a failed retry")
	store.reject_rollback = false
	store.fault = ""
	check(store.save(path,data).success and FileAccess.get_file_as_bytes(path+".previous") == raw,"R04 successful retry retains the binary original backup")

func check_exact_byte_readback(data: Dictionary):
	# Godot's UTF-8 String decoder drops a leading BOM. Both write stages must
	# reject unexpected bytes even when the decoded JSON text looks identical.
	for fault in ["bom_temp","bom_main"]:
		var path = "res://evidence/r1-save/exact-"+fault+".json"
		var store = FaultStore.new()
		check(store.save(path,data).success,"R04 "+fault+" fixture has a real prior save")
		var original = FileAccess.get_file_as_bytes(path)
		var updated = data.duplicate(true)
		updated.gold -= 1
		store.fault = fault
		check(not store.save(path,updated).success,"R04 "+fault+" unexpected BOM cannot satisfy exact-byte confirmation")
		check(FileAccess.get_file_as_bytes(path) == original,"R04 "+fault+" mismatch retains or restores the original bytes")
		store.fault = ""
		check(store.save(path,updated).success and FileAccess.get_file_as_bytes(path) == JSON.stringify(updated,"\t").to_utf8_buffer(),"R04 "+fault+" exact-byte retry persists the intended snapshot")
		check(FileAccess.get_file_as_bytes(path+".previous") == original,"R04 "+fault+" retry preserves the verified predecessor")

func check_protected_backup_identity(data: Dictionary):
	# A caller cannot redefine the protected predecessor by rereading an already
	# damaged .previous and supplying those new bytes as the expected original.
	var path = "res://evidence/r1-save/protected-identity.json"
	var store = FaultStore.new()
	check(store.save(path,data).success,"R04 protected identity starts from a real save")
	var original = FileAccess.get_file_as_bytes(path)
	var updated = data.duplicate(true)
	updated.gold -= 1
	store.fault = "readback"
	store.reject_rollback = true
	check(not store.save(path,updated).success,"R04 protected identity is established by failed readback rollback")
	var main_before = FileAccess.get_file_as_bytes(path)
	var damaged = PackedByteArray([98,97,100,255,0,10])
	var file = FileAccess.open(path+".previous",FileAccess.WRITE)
	file.store_buffer(damaged); file.close()
	store.reject_rollback = false
	check(not store.save(path,updated).success,"R04 a changed protected predecessor blocks ordinary retry")
	check(not store.restore_previous(path+".previous",path+".tmp",path,damaged),"R04 caller-supplied damaged bytes cannot redefine the protected original")
	check(FileAccess.get_file_as_bytes(path) == main_before and FileAccess.get_file_as_bytes(path+".previous") == damaged,"R04 rejected identity mismatch writes neither main nor previous")
	file = FileAccess.open(path+".previous",FileAccess.WRITE)
	file.store_buffer(original); file.close()
	store.fault = ""
	check(store.save(path,updated).success,"R04 restoring the actual protected bytes permits retry")
	check(FileAccess.get_file_as_bytes(path+".previous") == original and FileAccess.get_file_as_bytes(path) == JSON.stringify(updated,"\t").to_utf8_buffer(),"R04 identity recovery keeps the real predecessor and writes the desired state")

func check_restored_main_releases_protection(data: Dictionary):
	# Explicit discard can restore the committed bytes directly to the main
	# file. Once those exact bytes are present, a damaged backup must not keep
	# all future saves locked. A different valid snapshot is not restoration.
	for mode in ["missing","changed"]:
		var path = "res://evidence/r1-save/restored-main-"+mode+".json"
		var store = FaultStore.new()
		check(store.save(path,data).success,"R04 restored main "+mode+" starts from a real save")
		var original = FileAccess.get_file_as_bytes(path)
		var updated = data.duplicate(true)
		updated.gold -= 1
		var updated_bytes = JSON.stringify(updated,"\t").to_utf8_buffer()
		store.fault = "readback"
		store.reject_rollback = true
		check(not store.save(path,updated).success and not store.protected_previous_path(path).is_empty(),"R04 restored main "+mode+" establishes protection through a failed rollback")
		if mode == "missing":
			check(DirAccess.remove_absolute(path+".previous") == OK,"R04 restored main missing removes the backup for the fault fixture")
		else:
			var backup = FileAccess.open(path+".previous",FileAccess.WRITE)
			backup.store_buffer(PackedByteArray([98,97,100,255,0,10])); backup.close()
			check(not store.protected_previous_intact(path),"R04 restored main changed damages the backup for the fault fixture")
		store.fault = ""
		store.reject_rollback = false
		var file = FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(updated_bytes); file.close()
		check(not store.save(path,updated).success,"R04 restored main "+mode+" cannot release protection using a different valid snapshot")
		check(FileAccess.get_file_as_bytes(path) == updated_bytes and not store.protected_previous_path(path).is_empty(),"R04 restored main "+mode+" mismatch preserves both the main bytes and original identity")
		# This is the byte write performed by the existing committed-save discard
		# path, without claiming native execution exercises Web scene/UI behavior.
		file = FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(original); file.close()
		check(FileAccess.get_file_as_bytes(path) == original,"R04 restored main "+mode+" contains the committed original byte for byte")
		check(store.save(path,updated).success,"R04 restored main "+mode+" permits saving after exact original restoration")
		check(store.protected_previous_path(path).is_empty(),"R04 restored main "+mode+" releases the completed recovery identity")
		check(FileAccess.get_file_as_bytes(path) == updated_bytes and FileAccess.get_file_as_bytes(path+".previous") == original,"R04 restored main "+mode+" writes the desired state and reconstructs the original backup")
		var following = updated.duplicate(true)
		following.gold -= 1
		check(store.save(path,following).success and FileAccess.get_file_as_bytes(path+".previous") == updated_bytes,"R04 restored main "+mode+" resumes normal backup rotation")

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
	var faults = ["open","write","replace","readback"]
	for index in faults.size():
		var fault = faults[index]
		store.fault = fault
		var before = PlayerData.gold
		var count = Demo.owned_global_upgrades.size()
		var purchase = Demo.try_purchase("attachment",str(110+index))
		check(purchase.success and not purchase.saved and Demo.dirty,"R04 transaction succeeds but saving "+fault+" fails visibly")
		check(FileAccess.get_file_as_string(Demo.save_path) == previous,"R04 prior snapshot byte-identical after "+fault)
		if not purchase.success:
			get_tree().quit(1)
			return
		check(PlayerData.gold == before-purchase.charged_amount and Demo.owned_global_upgrades.size() == count+1,"R04 charged once "+fault)
		store.fault = ""
		check(Demo.save_camp().success and not Demo.dirty,"R04 retry saves "+fault)
		check(PlayerData.gold == before-purchase.charged_amount and Demo.owned_global_upgrades.size() == count+1,"R04 retry never charges or grants again")
		previous = FileAccess.get_file_as_string(Demo.save_path)
		var expected = Demo.snapshot().duplicate(true)
		var loaded = Demo.load_camp()
		check(loaded and Demo.snapshot().weapons == expected.weapons and PlayerData.gold == expected.gold,"R04 written content actually restores")
	check_backup_retries(data)
	check_exact_byte_readback(data)
	check_protected_backup_identity(data)
	check_restored_main_releases_protection(data)
	Demo.test_mode = true
	check(Utils.player.reward_root.get_node("REWARD BLUE BACTERIA").kill_count == 1000,"legacy bacteria lifetime cap survives load")
	var old = data.duplicate(true)
	old.attachments = []; old.next_instance = 1; old = M7Fixtures.legacy(old,1); old.erase("legacy_state")
	check(CampSnapshot.normalize(old).legacy_state["10"] == 1000,"v1 bacteria cap migrates from persisted HP")
	var cases = []
	var malformed = data.duplicate(true)
	malformed.owned_global_upgrades = ["unknown"]; cases.append(malformed)
	malformed = data.duplicate(true); malformed.weapons[0].ammo = 1.5; cases.append(malformed)
	malformed = data.duplicate(true); malformed.exp = PlayerData.getMaxExp(); cases.append(malformed)
	malformed = data.duplicate(true); malformed.hp = malformed.hp_max+1; cases.append(malformed)
	malformed = data.duplicate(true); malformed.legacy_state["10"] = 1001; cases.append(malformed)
	malformed = data.duplicate(true)
	malformed.owned_global_upgrades = ["110","110"]; cases.append(malformed)
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
	old = data.duplicate(true); old.attachments = []; old.next_instance = 1; old = M7Fixtures.legacy(old,1); old.erase("legacy"); old.erase("legacy_state")
	old.hp = 5; old.hp_max = 5
	check(Demo.valid_save(old),"R03 legal missing-legacy v1")
	data.legacy.append("0"); data.legacy.append("1"); data.hp = 0
	file = FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(Demo.load_camp() and PlayerData.gold == data.gold and PlayerData.player_hp == 0,"R03 old one-shot rewards neither regrant nor revive")
	print("R1 PERSISTENCE checks=",checks," failures=",failures)
	Demo.stop_attacks()
	await get_tree().create_timer(0.2,true).timeout
	get_tree().quit(1 if failures else 0)

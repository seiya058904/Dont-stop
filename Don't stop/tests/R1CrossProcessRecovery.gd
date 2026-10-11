extends Node

## Run this scene with the same isolated user directory:
## -- before, then -- after, then -- verify-archives. No fixture is deleted.
class FaultStore extends CampSaveStore:
	var reject_rollback = true
	var corrupt_replace = true
	func replace_file(source, destination):
		var result = super.replace_file(source,destination)
		if result == OK and corrupt_replace:
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt-after-replace"); file.close()
		return result
	func restore_previous(previous_path, temporary, path, expected):
		return false if reject_rollback else super.restore_previous(previous_path,temporary,path,expected)

class ArchiveFailureStore extends CampSaveStore:
	var refuse_archive = true
	func preserve_recovery_bytes(path, bytes):
		return "" if refuse_archive else super.preserve_recovery_bytes(path,bytes)

var checks = 0
var failures = 0
const PATH = "user://cross-process-camp.json"
const ORIGINAL = "user://cross-process-original.evidence"

func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)

func write_bytes(path: String, bytes: PackedByteArray):
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()

func check_legacy_recovery(original: PackedByteArray):
	# Upgrade a failure produced by the former version: there was no sidecar.
	for mode in ["damaged","missing"]:
		var path = "user://legacy-"+mode+".json"
		write_bytes(path+".previous",original)
		if mode == "damaged": write_bytes(path,"corrupt-old-main".to_utf8_buffer())
		Demo.save_path = path
		Demo.save_store = CampSaveStore.new()
		check(not FileAccess.file_exists(path+".recovery"),"legacy fixture has no recovery record "+mode)
		check(not Demo.load_camp() and Demo.save_blocked,"legacy unusable main enters blocked recovery "+mode)
		var exported = Demo.export_bad_save()
		var expected_export = "corrupt-old-main".to_utf8_buffer() if mode == "damaged" else original
		check(not exported.begins_with("导出失败") and FileAccess.get_file_as_bytes(exported) == expected_export,"legacy recovery keeps the existing original export contract "+mode)
		check(Demo.create_new_save(),"legacy explicit new-save path still succeeds "+mode)
		var archived = path+".recovered-"+Demo.save_store._hash_bytes(original)+".json"
		check(FileAccess.file_exists(archived) and FileAccess.get_file_as_bytes(archived) == original,"legacy new save preserves exact predecessor in independent archive "+mode)
		check(Demo.valid_save(JSON.parse_string(FileAccess.get_file_as_string(path))),"legacy takeover keeps the normal save format "+mode)
		write_bytes("user://legacy-"+mode+"-export-path.evidence",exported.to_utf8_buffer())

func check_archive_failures(original: PackedByteArray):
	for mode in ["damaged","missing"]:
		var path = "user://archive-refused-"+mode+".json"
		var damaged = "legacy-original-damaged".to_utf8_buffer()
		write_bytes(path+".previous",original)
		if mode == "damaged": write_bytes(path,damaged)
		Demo.save_path = path
		var store = ArchiveFailureStore.new()
		Demo.save_store = store
		check(not Demo.load_camp() and Demo.save_blocked,"archive failure blocks loading unusable main "+mode)
		check(not Demo.create_new_save() and Demo.save_blocked,"archive failure refuses explicit replacement "+mode)
		check(FileAccess.get_file_as_bytes(path+".previous") == original and (FileAccess.get_file_as_bytes(path) == damaged if mode == "damaged" else not FileAccess.file_exists(path)),"archive failure retains both original identities "+mode)
		store.refuse_archive = false
		check(Demo.create_new_save(),"archive failure can be retried without losing original identities "+mode)
		var archived = path+".recovered-"+store._hash_bytes(original)+".json"
		check(FileAccess.get_file_as_bytes(archived) == original,"archive retry retains exact predecessor bytes "+mode)
	var path = "user://archive-collision.json"
	var damaged = "collision-main-original".to_utf8_buffer()
	write_bytes(path,damaged); write_bytes(path+".previous",original)
	var store = CampSaveStore.new()
	var archived = path+".recovered-"+store._hash_bytes(original)+".json"
	var unrelated = "unrelated unique archive bytes".to_utf8_buffer()
	write_bytes(archived,unrelated)
	Demo.save_path = path; Demo.save_store = store
	Demo.load_camp()
	check(not Demo.create_new_save(),"different existing archive refuses replacement")
	check(FileAccess.get_file_as_bytes(archived) == unrelated and FileAccess.get_file_as_bytes(path) == damaged and FileAccess.get_file_as_bytes(path+".previous") == original,"archive collision never overwrites any unique bytes")
	check(DirAccess.rename_absolute(archived,archived+".collision-evidence") == OK,"archive collision repair retains the unrelated bytes")
	check(Demo.create_new_save() and FileAccess.get_file_as_bytes(archived) == original,"repaired archive collision allows explicit new save")
	check(store.preserve_recovery_bytes(path,original) == archived and FileAccess.get_file_as_bytes(archived) == original,"identical existing archive is accepted without modification")

func check_restarted_archives(original: PackedByteArray):
	for mode in ["damaged","missing"]:
		var path = "user://legacy-"+mode+".json"
		var store = CampSaveStore.new()
		var archived = path+".recovered-"+store._hash_bytes(original)+".json"
		check(FileAccess.get_file_as_bytes(archived) == original,"restarted process can recover the exact legacy predecessor "+mode)
		check(Demo.valid_save(JSON.parse_string(FileAccess.get_file_as_string(archived))),"restarted predecessor remains a valid schema-6 camp "+mode)
		var exported = FileAccess.get_file_as_string("user://legacy-"+mode+"-export-path.evidence")
		var expected = "corrupt-old-main".to_utf8_buffer() if mode == "damaged" else original
		check(FileAccess.get_file_as_bytes(exported) == expected,"restarted process still has the original export evidence "+mode)

func _ready():
	Demo.test_mode = true
	Demo.save_path = PATH
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	for frame in 5: await get_tree().process_frame
	var stage = OS.get_cmdline_user_args()[0]
	if stage.begins_with("before"):
		var data = Demo._initial_camp_snapshot()
		data.gold = 777
		check(Demo.valid_save(data),"schema-6 original is a real valid camp snapshot")
		var store = FaultStore.new()
		store.corrupt_replace = false
		check(store.save(PATH,data).success,"normal original save succeeds")
		var original = FileAccess.get_file_as_bytes(PATH)
		write_bytes(ORIGINAL,original)
		data.gold = 778
		store.corrupt_replace = true
		check(not store.save(PATH,data).success,"readback and rollback double failure is reported")
		check(FileAccess.get_file_as_bytes(PATH+".previous") == original,"first process keeps exact recoverable schema-6 bytes")
		check(not store.protected_previous_path(PATH).is_empty(),"first process records recovery protection")
	elif stage == "verify-archives":
		check_restarted_archives(FileAccess.get_file_as_bytes(ORIGINAL))
	else:
		var original = FileAccess.get_file_as_bytes(ORIGINAL)
		Demo.save_store = CampSaveStore.new()
		check(not Demo.load_camp() and Demo.save_blocked,"fresh process refuses the damaged main")
		var exported = Demo.export_bad_save()
		check(not exported.begins_with("导出失败") and FileAccess.get_file_as_bytes(exported) == original,"fresh process exports the protected original rather than damaged main")
		check(Demo.create_new_save(),"explicit new-save action completes through actual Demo path")
		check(FileAccess.get_file_as_bytes(PATH+".previous") == original,"explicit new-save never rotates damaged main over the unique predecessor")
		check(Demo.valid_save(JSON.parse_string(FileAccess.get_file_as_string(PATH))),"new camp remains schema-6 compatible")
		check(not Demo.save_blocked and not Demo.dirty and Demo.snapshot().gold == DemoConfig.INITIAL_GOLD,"new-save completion restores actual fresh gameplay state")
		check(FileAccess.get_file_as_bytes(exported) == original,"recovery export survives subsequent writes")
		check_legacy_recovery(original)
		check_archive_failures(original)
	print("R1 CROSS PROCESS ",stage," checks=",checks," failures=",failures)
	if stage == "before-kill": await get_tree().create_timer(60,true).timeout
	Demo.stop_attacks()
	await get_tree().create_timer(0.2,true).timeout
	get_tree().quit(1 if failures else 0)

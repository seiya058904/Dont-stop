extends Node

class FaultStore extends CampSaveStore:
	var reject_rollback = true
	func replace_file(source, destination):
		var result = super.replace_file(source,destination)
		if result == OK:
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt-after-replace"); file.close()
		return result
	func restore_previous(previous_path, temporary, path, expected):
		return false if reject_rollback else super.restore_previous(previous_path,temporary,path,expected)

class JournalFailureStore extends CampSaveStore:
	var refuse_active = false
	var refuse_completion = false
	func _write_recovery(path, record):
		if (record.active and refuse_active) or (not record.active and refuse_completion): return false
		return super._write_recovery(path,record)

var checks = 0
var failures = 0

func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)

func write_bytes(path: String, bytes: PackedByteArray):
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()

func faulted_fixture(path: String, data: Dictionary) -> PackedByteArray:
	check(CampSaveStore.new().save(path,data).success,"journal fixture has a normal first save")
	var original = FileAccess.get_file_as_bytes(path)
	write_bytes(path+".original-evidence",original)
	check(not FaultStore.new().save(path,{"schema_version":6,"gold":778}).success,"journal double failure is visible")
	return original

func _ready():
	var data = {"schema_version":6,"gold":777}
	for mode in ["missing","changed"]:
		var path = "user://journal-"+mode+".json"
		var original = faulted_fixture(path,data)
		var main_before = FileAccess.get_file_as_bytes(path)
		if mode == "missing":
			check(DirAccess.rename_absolute(path+".previous",path+".previous-missing-evidence") == OK,"missing backup fault retains the original under another name")
		else:
			write_bytes(path+".previous","different backup".to_utf8_buffer())
		var store = CampSaveStore.new()
		check(not store.protected_previous_path(path).is_empty() and not store.protected_previous_intact(path),"fresh store fails closed for "+mode+" predecessor")
		check(not store.save(path,data).success and FileAccess.get_file_as_bytes(path) == main_before,"unavailable predecessor cannot overwrite main "+mode)
		write_bytes(path+".previous",original)
		check(store.protected_previous_intact(path),"repairing exact predecessor restores recovery eligibility "+mode)
		check(store.save(path,data).success and FileAccess.get_file_as_bytes(path+".previous") == original,"repaired predecessor permits a byte-preserving retry "+mode)
		check(store.protected_previous_path(path).is_empty(),"completed recovery releases protection "+mode)
	for marker in ["{",'{"version":99,"active":true}','{"version":1,"active":true,"original_sha256":"wrong"}']:
		var path = "user://journal-invalid-"+str(checks)+".json"
		check(CampSaveStore.new().save(path,data).success,"invalid marker fixture starts from a normal save")
		var original = FileAccess.get_file_as_bytes(path)
		write_bytes(path+".original-evidence",original)
		write_bytes(path+".recovery",marker.to_utf8_buffer())
		var store = CampSaveStore.new()
		check(not store.protected_previous_intact(path) and not store.save(path,data).success,"malformed or unsupported journal fails closed")
		check(FileAccess.get_file_as_bytes(path) == original,"invalid journal does not mutate original main")
	var path = "user://journal-write-refused.json"
	var store = JournalFailureStore.new()
	check(store.save(path,data).success,"journal write-failure fixture starts normally")
	var original = FileAccess.get_file_as_bytes(path)
	store.refuse_active = true
	check(not store.save(path,{"gold":778}).success and FileAccess.get_file_as_bytes(path) == original,"failed protection write prevents replacement")
	store.refuse_active = false
	store.refuse_completion = true
	var candidate = {"gold":779}
	check(not store.save(path,candidate).success,"failed completion is reported rather than claiming success")
	var candidate_bytes = JSON.stringify(candidate,"\t").to_utf8_buffer()
	check(FileAccess.get_file_as_bytes(path) == candidate_bytes and FileAccess.get_file_as_bytes(path+".previous") == original,"completion fault leaves both transaction versions recoverable")
	var fresh = CampSaveStore.new()
	check(fresh.protected_previous_path(path).is_empty(),"fresh store recognizes exact committed candidate after interrupted completion")
	check(fresh.save(path,{"gold":780}).success and FileAccess.get_file_as_bytes(path+".previous") == candidate_bytes,"subsequent save does not roll back a completed candidate")
	path = "user://journal-restored-main.json"
	original = faulted_fixture(path,data)
	check(DirAccess.rename_absolute(path+".previous",path+".previous-missing-evidence") == OK,"external repair scenario retains missing-backup evidence")
	write_bytes(path,original)
	fresh = CampSaveStore.new()
	check(fresh.protected_previous_path(path).is_empty() and fresh.save(path,data).success,"exact restored main releases recovery even when backup is missing")
	path = "user://journal-protection-retry.json"
	store = JournalFailureStore.new()
	check(store.save(path,data).success,"protection retry starts with a normal original")
	original = FileAccess.get_file_as_bytes(path)
	write_bytes(path+".previous",original)
	write_bytes(path+".original-evidence",original)
	write_bytes(path,"damaged main".to_utf8_buffer())
	store.refuse_active = true
	store.protect_previous(path,original)
	check(not store.protected_previous_intact(path) and not store.save(path,data).success,"failed original-identity journal write holds the lock")
	store.refuse_active = false
	check(store.protected_previous_intact(path) and store.save(path,data).success,"journal protection is retryable using only the captured exact identity")
	check(FileAccess.get_file_as_bytes(path+".previous") == original,"journal retry keeps the authoritative predecessor")
	path = "user://journal-same-process-discard.json"
	check(CampSaveStore.new().save(path,data).success,"same-process discard fixture starts with a normal save")
	original = FileAccess.get_file_as_bytes(path)
	var held = FaultStore.new()
	check(not held.save(path,{"gold":778}).success,"same-process failed rollback captures the predecessor")
	check(DirAccess.rename_absolute(path,path+".unreadable-evidence") == OK,"same-process read fault retains main evidence")
	check(not held.protected_previous_path(path).is_empty(),"unreadable main cannot release the captured predecessor")
	write_bytes(path,JSON.stringify({"gold":779},"\t").to_utf8_buffer())
	check(not held.protected_previous_path(path).is_empty(),"different main bytes cannot release the captured predecessor")
	write_bytes(path,original)
	check(held.protected_previous_path(path).is_empty(),"exact same-process discard releases protection before another save")
	path = "user://journal-discard-completion-refused.json"
	store = JournalFailureStore.new()
	check(store.save(path,data).success,"discard completion refusal starts normally")
	original = FileAccess.get_file_as_bytes(path)
	store.refuse_completion = true
	check(not store.save(path,{"gold":778}).success,"discard completion refusal reports the pending journal")
	write_bytes(path,original)
	check(not store.protected_previous_path(path).is_empty(),"exact restored main remains blocked when journal completion is refused")
	check(FileAccess.get_file_as_bytes(path) == original,"refused completion preserves restored main bytes")
	store.refuse_completion = false
	check(store.protected_previous_path(path).is_empty(),"exact restoration retries journal completion safely")
	for bytes in [PackedByteArray(),"正常中文🙂".to_utf8_buffer(),PackedByteArray([0xc2,0x80]),PackedByteArray([0xe0,0xa0,0x80]),PackedByteArray([0xf4,0x8f,0xbf,0xbf])]:
		check(store.valid_utf8(bytes),"legacy UTF-8 validator accepts valid complete encoding")
	for bytes in [PackedByteArray([0x80]),PackedByteArray([0xc0,0x80]),PackedByteArray([0xe0,0x80,0x80]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80]),PackedByteArray([0xf0,0x90])]:
		check(not store.valid_utf8(bytes),"legacy UTF-8 validator rejects invalid encoding without decoding it")
	print("R1 RECOVERY JOURNAL checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

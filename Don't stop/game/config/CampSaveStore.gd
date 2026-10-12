extends RefCounted
class_name CampSaveStore

signal web_confirmed(revision: int, success: bool, reason: String)
var _web_callback
## Only populated after a failed rollback. A retry must restore this verified
## predecessor before save() may rotate .previous again.
var _pending_rollbacks: Dictionary = {}
var _recovery_errors: Dictionary = {}

# force_fs_sync has no completion result. Confirm the exact bytes in a separate
# IndexedDB read transaction, after commit, rather than reading MEMFS again.
const WEB_CONFIRM = """
window.towdownSave = window.towdownSave || {
 dirty: false,
 diagnosticsEnabled: false,
 diagnostics: [],
 record(event, fields = {}, detailed = false) {
  if (detailed && !this.diagnosticsEnabled) return;
  const entry = Object.assign({ event, at: new Date().toISOString(), elapsed_ms: performance.now() }, fields);
  this.diagnostics.push(entry);
  const limit = this.diagnosticsEnabled ? 4000 : 64;
  if (this.diagnostics.length > limit) this.diagnostics.splice(0, this.diagnostics.length - limit);
 },
 verify(path, text, revision, callback) {
  const started = performance.now();
  const hardDeadline = started + 18000;
  const trace = (event, fields = {}, detailed = false) => this.record(event, Object.assign({ revision, elapsed_ms: performance.now() - started }, fields), detailed);
  const hashBytes = this.diagnosticsEnabled ? bytes => {
   let hash = 0x811c9dc5;
   for (const byte of bytes) { hash ^= byte; hash = Math.imul(hash, 0x01000193); }
   return (hash >>> 0).toString(16).padStart(8, '0');
  } : null;
  // Decoding can discard a BOM or replace invalid UTF-8. Persistence confirms
  // the submitted bytes, including their length, rather than a decoded alias.
  const expectedBytes = new TextEncoder().encode(text);
  const expectedHash = this.diagnosticsEnabled ? hashBytes(expectedBytes) : null;
  let pollNumber = 0, observedRow = false;
  trace('verify-start', { path, expected_hash: expectedHash, expected_bytes: expectedBytes ? expectedBytes.length : null });
  this.dirty = true;
  let finished = false, db = null;
  const finish = (ok, reason) => {
   if (finished) return;
   finished = true; clearTimeout(timeout);
   trace('verify-callback', { success: ok, reason });
   if (db) db.close();
   callback(revision, ok, reason);
  };
  // Keep the existing fast confirmation window, then allow one evidence-based
  // commit grace period: the CI trace observed this exact snapshot at 13.14 s.
  let timeout = setTimeout(() => {
   trace('verify-slow-path', { fast_deadline_ms: 8000, grace_ms: 10000 });
   timeout = setTimeout(() => {
    trace('verify-timeout', { total_deadline_ms: 18000 });
    finish(false, '浏览器持久化未确认；进度仍在内存，请重试或导出');
   }, 10000);
  }, 8000);
  try {
   trace('open-start', { database: '/userfs' }, true);
   const open = indexedDB.open('/userfs');
   open.onerror = () => { trace('open-error', { error: String(open.error || '') }); finish(false, '浏览器存储不可用；请重试或导出当前进度'); };
   open.onblocked = () => { trace('open-blocked'); finish(false, '浏览器存储被阻止；请关闭同源游戏页后重试'); };
   open.onsuccess = () => {
    db = open.result;
    trace('open-success', { database: db.name, version: db.version, stores: Array.from(db.objectStoreNames) }, true);
    if (finished) { db.close(); return; }
    if (!db.objectStoreNames.contains('FILE_DATA')) return finish(false, '浏览器未启用持久化；请导出当前进度');
    const poll = () => {
     if (finished) return;
     const currentPoll = ++pollNumber;
     trace('poll-start', { poll: currentPoll }, true);
     try {
      const tx = db.transaction('FILE_DATA', 'readonly');
      const read = tx.objectStore('FILE_DATA').get(path);
      let matches = false;
      read.onsuccess = () => {
       const row = read.result;
       const contents = row && row.contents;
       const bytes = contents instanceof ArrayBuffer ? new Uint8Array(contents)
        : ArrayBuffer.isView(contents) ? new Uint8Array(contents.buffer, contents.byteOffset, contents.byteLength) : null;
       matches = !!bytes && bytes.length === expectedBytes.length && bytes.every((byte, index) => byte === expectedBytes[index]);
       if (row && hashBytes) {
        const rowHash = bytes ? hashBytes(bytes) : null;
        const rowLength = bytes ? bytes.length : null;
        trace('row-hash', { poll: currentPoll, row_hash: rowHash, row_bytes: rowLength, expected_hash: expectedHash, match: matches }, true);
        if (!observedRow) { observedRow = true; trace('first-row', { poll: currentPoll, row_hash: rowHash, row_bytes: rowLength, match: matches }, true); }
       } else if (!row && hashBytes) trace('row-missing', { poll: currentPoll, expected_hash: expectedHash }, true);
      };
      tx.oncomplete = () => {
       trace('transaction-complete', { poll: currentPoll, match: matches }, true);
       if (matches && performance.now() >= hardDeadline) {
        trace('verify-timeout', { total_deadline_ms: 18000, observed_after_deadline: true });
        finish(false, '浏览器持久化未确认；进度仍在内存，请重试或导出');
       }
       else if (matches) { trace('verify-match', { poll: currentPoll, expected_hash: expectedHash }); finish(true, '已保存到浏览器'); }
       else setTimeout(poll, 100);
      };
      tx.onabort = () => { trace('transaction-abort', { poll: currentPoll, error: String(tx.error || '') }); finish(false, '浏览器存储读取失败；请重试或导出当前进度'); };
      tx.onerror = () => { trace('transaction-error', { poll: currentPoll, error: String(tx.error || '') }); finish(false, '浏览器存储读取失败；请重试或导出当前进度'); };
     } catch (e) { trace('poll-error', { poll: currentPoll, error: String(e) }); finish(false, '浏览器存储不可用；请重试或导出当前进度'); }
    };
    poll();
   };
  } catch (e) { trace('verify-error', { error: String(e) }); finish(false, '浏览器存储不可用；请重试或导出当前进度'); }
 }
};
if (!window.towdownSaveUnload) {
 window.towdownSaveUnload = true;
 window.addEventListener('beforeunload', e => {
  if (window.towdownSave.dirty) { e.preventDefault(); e.returnValue = ''; }
 });
}
"""

func _ensure_web_bridge() -> void:
	if _web_callback == null:
		JavaScriptBridge.eval(WEB_CONFIRM, true)
		_web_callback = JavaScriptBridge.create_callback(func(args): web_confirmed.emit(int(args[0]),bool(args[1]),str(args[2])))

func confirm_web(path: String, revision: int) -> void:
	_ensure_web_bridge()
	JavaScriptBridge.get_interface("towdownSave").verify(ProjectSettings.globalize_path(path),FileAccess.get_file_as_string(path),revision,_web_callback)
	JavaScriptBridge.eval("if (window.towdownSave) window.towdownSave.record('force-fs-sync-start', {revision:" + str(revision) + "})",true)
	JavaScriptBridge.force_fs_sync()

func mark_web_dirty(value: bool) -> void:
	if OS.has_feature("web"):
		_ensure_web_bridge()
		JavaScriptBridge.eval("if (window.towdownSave) window.towdownSave.dirty = " + ("true" if value else "false"),true)

func open_temp(path: String):
	return FileAccess.open(path,FileAccess.WRITE)

func write_temp(file: FileAccess, text: String) -> Error:
	file.store_string(text)
	if file.get_error() != OK: return file.get_error()
	file.flush()
	return file.get_error()

func replace_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source,destination)

func _hash_bytes(bytes: PackedByteArray) -> String:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _matches_hash(path: String, expected: String) -> bool:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return false
	var bytes = file.get_buffer(file.get_length())
	var error = file.get_error()
	file.close()
	return error == OK and _hash_bytes(bytes) == expected

func preserve_recovery_bytes(path: String, bytes: PackedByteArray) -> String:
	# Legacy transactions had no identity record. Preserve their predecessor
	# independently instead of guessing that it owns the current damaged main.
	var destination = path+".recovered-"+_hash_bytes(bytes)+".json"
	if FileAccess.file_exists(destination):
		return destination if _matches_bytes(destination,bytes) else ""
	var temporary = destination+".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return ""
	file.store_buffer(bytes)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or not _matches_bytes(temporary,bytes): return ""
	if FileAccess.file_exists(destination):
		return destination if _matches_bytes(destination,bytes) else ""
	if DirAccess.rename_absolute(temporary,destination) != OK: return ""
	return destination if _matches_bytes(destination,bytes) else ""

func _matches_bytes(path: String, expected: PackedByteArray) -> bool:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return false
	var bytes = file.get_buffer(file.get_length())
	var error = file.get_error()
	file.close()
	return error == OK and bytes == expected

func valid_utf8(bytes: PackedByteArray) -> bool:
	var remaining = 0
	var minimum = 0x80
	var maximum = 0xbf
	for byte in bytes:
		if remaining > 0:
			if byte < minimum or byte > maximum: return false
			remaining -= 1
			minimum = 0x80; maximum = 0xbf
		elif byte <= 0x7f: continue
		elif byte >= 0xc2 and byte <= 0xdf: remaining = 1
		elif byte >= 0xe0 and byte <= 0xef:
			remaining = 2
			minimum = 0xa0 if byte == 0xe0 else 0x80
			maximum = 0x9f if byte == 0xed else 0xbf
		elif byte >= 0xf0 and byte <= 0xf4:
			remaining = 3
			minimum = 0x90 if byte == 0xf0 else 0x80
			maximum = 0x8f if byte == 0xf4 else 0xbf
		else: return false
	return remaining == 0

func _write_recovery(path: String, record: Dictionary) -> bool:
	# Write/read back a separate sidecar before replacing either identity. An
	# incomplete sidecar never replaces the last authoritative recovery record.
	var destination = path+".recovery"
	var temporary = destination+".tmp"
	var bytes = JSON.stringify(record).to_utf8_buffer()
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var error = file.get_error()
	file.close()
	return error == OK and FileAccess.get_file_as_bytes(temporary) == bytes and DirAccess.rename_absolute(temporary,destination) == OK and FileAccess.get_file_as_bytes(destination) == bytes

func complete_recovery(path: String) -> bool:
	# Keep an inactive record rather than deleting a file. If this write fails,
	# the active record still pins the predecessor; a fresh process may recognize
	# an exactly written candidate as a completed transaction.
	if FileAccess.file_exists(path+".recovery") and not _write_recovery(path,{"version":1,"active":false}): return false
	_pending_rollbacks.erase(path)
	_recovery_errors.erase(path)
	return true

func _load_recovery(path: String) -> void:
	if _pending_rollbacks.has(path):
		# Explicit Web discard restores the exact committed predecessor before
		# the next load. Recognize that terminal state in this process too, rather
		# than blocking load_camp until a save (which startup never reaches).
		var restored = FileAccess.open(path,FileAccess.READ)
		if restored != null:
			var bytes = restored.get_buffer(restored.get_length())
			var read_error = restored.get_error()
			restored.close()
			if read_error == OK and bytes == _pending_rollbacks[path]:
				if not complete_recovery(path): _recovery_errors[path] = true
				return
		# A transient journal write failure is retryable while this process still
		# owns the verified predecessor identity. Never adopt reread backup bytes.
		if _recovery_errors.has(path) and _write_recovery(path,{"version":1,"active":true,"original_sha256":_hash_bytes(_pending_rollbacks[path]),"candidate_sha256":""}):
			_recovery_errors.erase(path)
		return
	_recovery_errors.erase(path)
	if not FileAccess.file_exists(path+".recovery"): return
	var parser = JSON.new()
	var error = parser.parse(FileAccess.get_file_as_string(path+".recovery"))
	var record = parser.data if error == OK else null
	if not record is Dictionary or record.get("version") != 1 or not record.get("active") is bool:
		_recovery_errors[path] = true
		return
	if not record.active: return
	var original = record.get("original_sha256","")
	var candidate = record.get("candidate_sha256","")
	if not original is String or original.length() != 64 or not original.is_valid_hex_number(false) or not candidate is String or (not candidate.is_empty() and (candidate.length() != 64 or not candidate.is_valid_hex_number(false))):
		_recovery_errors[path] = true
		return
	# On reload the file is read from the native filesystem / hydrated userfs,
	# rather than the former process's staged memory. Either exact terminal state
	# finishes the interrupted transaction without undoing a completed save.
	if _matches_hash(path,original) or (not candidate.is_empty() and _matches_hash(path,candidate)):
		if not complete_recovery(path): _recovery_errors[path] = true
	elif _matches_hash(path+".previous",original):
		_pending_rollbacks[path] = FileAccess.get_file_as_bytes(path+".previous")
	else:
		_recovery_errors[path] = true

func protected_previous_path(path: String) -> String:
	_load_recovery(path)
	return path+".previous" if _pending_rollbacks.has(path) or _recovery_errors.has(path) else ""

func protect_previous(path: String, original: PackedByteArray) -> void:
	# The first failed transaction owns this identity until exact restoration.
	# A later caller cannot replace it with newly read, damaged backup bytes.
	if not _pending_rollbacks.has(path): _pending_rollbacks[path] = original.duplicate()
	# A failed confirmation cannot be treated as a completed candidate on reload.
	if not _write_recovery(path,{"version":1,"active":true,"original_sha256":_hash_bytes(_pending_rollbacks[path]),"candidate_sha256":""}):
		_recovery_errors[path] = true

func protected_previous_intact(path: String) -> bool:
	_load_recovery(path)
	if _recovery_errors.has(path): return false
	return not _pending_rollbacks.has(path) or (FileAccess.file_exists(path+".previous") and FileAccess.get_file_as_bytes(path+".previous") == _pending_rollbacks[path])

func save(path: String, data: Dictionary) -> Dictionary:
	_load_recovery(path)
	if _pending_rollbacks.has(path):
		# An explicit discard or external repair can already have restored the
		# exact pinned main snapshot. Do not keep rejecting future saves merely
		# because the old backup is now unavailable. A successful read is required.
		var restored_file = FileAccess.open(path,FileAccess.READ)
		if restored_file != null:
			var restored_bytes = restored_file.get_buffer(restored_file.get_length())
			var restored_error = restored_file.get_error()
			restored_file.close()
			if restored_error == OK and restored_bytes == _pending_rollbacks[path]:
				if not complete_recovery(path): return {"success":false,"reason":"恢复记录无法确认；原文保持，请重试保存"}
	if _recovery_errors.has(path):
		return {"success":false,"reason":"恢复记录或原文备份缺失、损坏；请检查 .recovery 和 .previous 后重试"}
	if _pending_rollbacks.has(path):
		var protected_bytes: PackedByteArray = _pending_rollbacks[path]
		if not protected_previous_intact(path) or not restore_previous(path+".previous",path+".tmp",path,protected_bytes):
			return {"success":false,"reason":"上一快照尚未恢复；请检查 .previous 备份后重试保存"}
		_pending_rollbacks.erase(path)
	var text = JSON.stringify(data,"\t")
	var expected_bytes := text.to_utf8_buffer()
	var temporary = path+".tmp"
	var file = open_temp(temporary)
	if file == null: return {"success":false,"reason":"无法打开临时存档"}
	var error = write_temp(file,text)
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != expected_bytes:
		return {"success":false,"reason":"写入或刷新存档失败"}
	var previous_path = path+".previous"
	var had_previous = FileAccess.file_exists(path)
	var previous_bytes = FileAccess.get_file_as_bytes(path) if had_previous else PackedByteArray()
	if had_previous:
		if DirAccess.copy_absolute(path,previous_path) != OK or FileAccess.get_file_as_bytes(previous_path) != previous_bytes:
			return {"success":false,"reason":"保留上一快照失败；原存档未替换"}
		if not _write_recovery(path,{"version":1,"active":true,"original_sha256":_hash_bytes(previous_bytes),"candidate_sha256":_hash_bytes(expected_bytes)}):
			return {"success":false,"reason":"恢复保护记录写入失败；原存档未替换"}
		_pending_rollbacks[path] = previous_bytes.duplicate()
	if replace_file(temporary,path) != OK:
		return {"success":false,"reason":"替换存档失败，上一份快照已保留"}
	if FileAccess.get_file_as_bytes(path) != expected_bytes:
		if had_previous and restore_previous(previous_path,temporary,path,previous_bytes):
			return {"success":false,"reason":"存档回读不一致；已恢复上一份快照"}
		if had_previous: protect_previous(path,previous_bytes)
		return {"success":false,"reason":"存档回读不一致；上一快照保留在.previous文件，请重试保存" if had_previous else "首次存档回读失败；请重试保存"}
	if OS.has_feature("web"):
		return {"success":false,"pending":true,"memory_written":true,"reason":"进度在内存中；正在确认浏览器持久化…"}
	if not complete_recovery(path): return {"success":false,"reason":"存档已写入但恢复记录未确认；请重试保存"}
	return {"success":true,"reason":"已保存"}

func restore_previous(previous_path: String, temporary: String, path: String, expected) -> bool:
	# Keep the backup even if storage remains unavailable during rollback.
	# String callers remain supported; production recovery passes original bytes
	# so an invalid UTF-8 document is never decoded and rewritten during rollback.
	var original: PackedByteArray = expected if expected is PackedByteArray else str(expected).to_utf8_buffer()
	_load_recovery(path)
	if _recovery_errors.has(path): return false
	if _pending_rollbacks.has(path) and original != _pending_rollbacks[path]: return false
	if not FileAccess.file_exists(previous_path) or FileAccess.get_file_as_bytes(previous_path) != original: return false
	if DirAccess.copy_absolute(previous_path,temporary) != OK or FileAccess.get_file_as_bytes(temporary) != original: return false
	if DirAccess.rename_absolute(temporary,path) != OK: return false
	if FileAccess.get_file_as_bytes(path) != original: return false
	return complete_recovery(path)

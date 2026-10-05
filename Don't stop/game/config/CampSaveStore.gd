extends RefCounted
class_name CampSaveStore

signal web_confirmed(revision: int, success: bool, reason: String)
var _web_callback

# force_fs_sync has no completion result. Confirm the exact bytes in a separate
# IndexedDB read transaction, after commit, rather than reading MEMFS again.
const WEB_CONFIRM = """
window.towdownSave = window.towdownSave || {
 dirty: false,
 diagnostics: [],
 record(event, fields = {}) {
  const entry = Object.assign({ event, at: new Date().toISOString(), elapsed_ms: performance.now() }, fields);
  this.diagnostics.push(entry);
  if (this.diagnostics.length > 4000) this.diagnostics.splice(0, this.diagnostics.length - 4000);
 },
 verify(path, text, revision, callback) {
  const started = performance.now();
  const trace = (event, fields = {}) => this.record(event, Object.assign({ revision, elapsed_ms: performance.now() - started }, fields));
  const hashBytes = bytes => {
   let hash = 0x811c9dc5;
   for (const byte of bytes) { hash ^= byte; hash = Math.imul(hash, 0x01000193); }
   return (hash >>> 0).toString(16).padStart(8, '0');
  };
  const expectedBytes = new TextEncoder().encode(text);
  const expectedHash = hashBytes(expectedBytes);
  let pollNumber = 0, observedRow = false;
  trace('verify-start', { path, expected_hash: expectedHash, expected_bytes: expectedBytes.length });
  this.dirty = true;
  let finished = false, db = null;
  const finish = (ok, reason) => {
   if (finished) return;
   finished = true; clearTimeout(timeout);
   trace('verify-callback', { success: ok, reason });
   if (db) db.close();
   callback(revision, ok, reason);
  };
  const timeout = setTimeout(() => { trace('verify-timeout'); finish(false, '浏览器持久化未确认；进度仍在内存，请重试或导出'); }, 8000);
  try {
   trace('open-start', { database: '/userfs' });
   const open = indexedDB.open('/userfs');
   open.onerror = () => { trace('open-error', { error: String(open.error || '') }); finish(false, '浏览器存储不可用；请重试或导出当前进度'); };
   open.onblocked = () => { trace('open-blocked'); finish(false, '浏览器存储被阻止；请关闭同源游戏页后重试'); };
   open.onsuccess = () => {
    db = open.result;
    trace('open-success', { database: db.name, version: db.version, stores: Array.from(db.objectStoreNames) });
    if (finished) { db.close(); return; }
    if (!db.objectStoreNames.contains('FILE_DATA')) return finish(false, '浏览器未启用持久化；请导出当前进度');
    const poll = () => {
     if (finished) return;
     const currentPoll = ++pollNumber;
     trace('poll-start', { poll: currentPoll });
     try {
      const tx = db.transaction('FILE_DATA', 'readonly');
      const read = tx.objectStore('FILE_DATA').get(path);
      let matches = false;
      read.onsuccess = () => {
       const row = read.result;
       matches = !!row && new TextDecoder().decode(row.contents) === text;
       if (row) {
        const bytes = row.contents instanceof Uint8Array ? row.contents : new Uint8Array(row.contents);
        const rowHash = hashBytes(bytes);
        trace('row-hash', { poll: currentPoll, row_hash: rowHash, row_bytes: bytes.length, expected_hash: expectedHash, match: matches });
        if (!observedRow) { observedRow = true; trace('first-row', { poll: currentPoll, row_hash: rowHash, row_bytes: bytes.length, match: matches }); }
       } else trace('row-missing', { poll: currentPoll, expected_hash: expectedHash });
      };
      tx.oncomplete = () => {
       trace('transaction-complete', { poll: currentPoll, match: matches });
       if (matches) { trace('verify-match', { poll: currentPoll, expected_hash: expectedHash }); finish(true, '已保存到浏览器'); }
       else setTimeout(poll, 100);
      };
      tx.onabort = () => { trace('transaction-abort', { poll: currentPoll, error: String(tx.error || '') }); finish(false, '浏览器存储读取失败；请重试或导出当前进度'); };
      tx.onerror = () => trace('transaction-error', { poll: currentPoll, error: String(tx.error || '') });
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

func save(path: String, data: Dictionary) -> Dictionary:
	var text = JSON.stringify(data,"\t")
	var temporary = path+".tmp"
	var file = open_temp(temporary)
	if file == null: return {"success":false,"reason":"无法打开临时存档"}
	var error = write_temp(file,text)
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != text:
		return {"success":false,"reason":"写入或刷新存档失败"}
	var previous_path = path+".previous"
	var had_previous = FileAccess.file_exists(path)
	var previous_text = FileAccess.get_file_as_string(path) if had_previous else ""
	if had_previous:
		if DirAccess.copy_absolute(path,previous_path) != OK or FileAccess.get_file_as_string(previous_path) != previous_text:
			return {"success":false,"reason":"保留上一快照失败；原存档未替换"}
	if replace_file(temporary,path) != OK:
		return {"success":false,"reason":"替换存档失败，上一份快照已保留"}
	if FileAccess.get_file_as_string(path) != text:
		if had_previous and restore_previous(previous_path,temporary,path,previous_text):
			return {"success":false,"reason":"存档回读不一致；已恢复上一份快照"}
		return {"success":false,"reason":"存档回读不一致；上一快照保留在.previous文件，请重试保存" if had_previous else "首次存档回读失败；请重试保存"}
	if OS.has_feature("web"):
		return {"success":false,"pending":true,"memory_written":true,"reason":"进度在内存中；正在确认浏览器持久化…"}
	return {"success":true,"reason":"已保存"}

func restore_previous(previous_path: String, temporary: String, path: String, text: String) -> bool:
	# Keep the backup even if storage remains unavailable during rollback.
	if DirAccess.copy_absolute(previous_path,temporary) != OK or FileAccess.get_file_as_string(temporary) != text: return false
	if DirAccess.rename_absolute(temporary,path) != OK: return false
	return FileAccess.get_file_as_string(path) == text

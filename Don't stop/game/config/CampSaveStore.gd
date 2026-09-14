extends RefCounted
class_name CampSaveStore

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
	return {"success":true,"reason":"已保存"}

func restore_previous(previous_path: String, temporary: String, path: String, text: String) -> bool:
	# Keep the backup even if storage remains unavailable during rollback.
	if DirAccess.copy_absolute(previous_path,temporary) != OK or FileAccess.get_file_as_string(temporary) != text: return false
	if DirAccess.rename_absolute(temporary,path) != OK: return false
	return FileAccess.get_file_as_string(path) == text

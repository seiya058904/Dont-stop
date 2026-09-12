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
	if replace_file(temporary,path) != OK:
		return {"success":false,"reason":"替换存档失败，上一份快照已保留"}
	if FileAccess.get_file_as_string(path) != text:
		return {"success":false,"reason":"存档回读不一致"}
	return {"success":true,"reason":"已保存"}

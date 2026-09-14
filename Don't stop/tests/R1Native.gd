extends Node
# Manual/native automation fixture. Product UI and inputs are unchanged.
func _ready():
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-native")
	Demo.save_path = "res://evidence/r1-native/camp.json"
	if "bad-save" in OS.get_cmdline_user_args():
		Demo.save_path = "res://evidence/r1-native/bad.json"
		var file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
		file.store_string('{"legacy":'); file.close()
	add_child(load("res://game/map/Main.tscn").instantiate())

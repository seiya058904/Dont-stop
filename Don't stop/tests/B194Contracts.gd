extends Node

func _ready() -> void:
	var failures := 0
	# Import alone does not compile every lazily loaded diagnostic script.
	# Load in the real autoload environment; standalone --script lacks it.
	for path in ["res://game/diag/B11Stress.gd", "res://autoload/Warmup.gd", "res://ui/MainUI.gd", "res://boot/Boot.gd"]:
		var script = load(path)
		var valid: bool = script is GDScript and script.can_instantiate()
		print(("PASS " if valid else "FAIL ") + "lazy script compiles: " + path)
		if not valid: failures += 1
	for path in ["res://fonts/fusion-pixel.otf", "res://Sprites/1 cursor.png"]:
		var resource = load(path)
		var valid := resource != null
		print(("PASS " if valid else "FAIL ") + "imported boot resource loads: " + path)
		if not valid: failures += 1
	get_tree().quit(1 if failures else 0)

extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	var build=load("res://tests/M11Builds.gd").install("B")
	check(build.failures.is_empty(),"M10 reference legal build")
	var file=FileAccess.open("res://docs/iteration/evidence/m11/m10-save.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"save":Demo.snapshot(),"effective":Utils.player.gun.effective},"\t")); file.close()
	print("M11_SAVE_PROBE_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()

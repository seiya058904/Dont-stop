extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/m10-mature-save.json"))
	Demo.save_path="res://docs/iteration/evidence/m11/genuine-legacy-save.json"
	var file=FileAccess.open(Demo.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture.save)); file.close()
	for attempt in 3:
		check(Demo.load_camp(),"genuine M10 schema6 load "+str(attempt))
		var restored=JSON.parse_string(JSON.stringify(Demo.snapshot()))
		for key in fixture.save:
			check(restored.get(key)==fixture.save[key],"M10 saved field preserved "+key)
		for key in fixture.effective:
			var actual=Utils.player.gun.effective.get(key)
			var original=fixture.effective[key]
			check(is_equal_approx(float(actual),float(original)) if original is float or original is int else actual==original,"M10 effective stat preserved "+key)
	print("M11_SAVE_MIGRATION_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()

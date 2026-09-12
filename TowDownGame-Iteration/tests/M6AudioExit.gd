extends Node
# Minimal audio teardown isolation: no combat, UI, scene, timer or weapon nodes.
func _ready():
	Demo.test_mode = true
	var voice = AudioStreamPlayer.new(); add_child(voice)
	voice.stream = load("res://audio/bgm/Cephalopod.mp3")
	for cycle in 12:
		voice.play(); await get_tree().create_timer(0.15).timeout
		voice.stop(); await get_tree().create_timer(0.15).timeout
		print("AUDIO CYCLE ",cycle," objects=",Performance.get_monitor(Performance.OBJECT_COUNT)," resources=",Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)," stream_id=",voice.stream.get_instance_id()," refs=",voice.stream.get_reference_count())
	if "playing" in OS.get_cmdline_user_args(): voice.play(); await get_tree().create_timer(0.1).timeout
	if "normal" in OS.get_cmdline_user_args(): await Demo.quit_game()
	else: get_tree().quit()

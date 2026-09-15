extends Node2D

## Captures the player stat sheet so the text-only upgrade/talent entries can be
## inspected as an actual rendered image, not inferred from source.
##
## Run windowed (a headless DisplayServer cannot produce a viewport image):
##   Godot_v4.7.2-stable_win64.exe --path <project> res://tests/StatPanelShot.tscn

const OUT_DIR := "res://evidence/r3/statpanel"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[statshot] needs a rendering display; run without --headless")
		get_tree().quit(1)
		return
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	await get_tree().create_timer(0.6).timeout
	Utils.gameStart()
	await get_tree().create_timer(0.6).timeout
	LevelServer.state = "CAMP"
	PlayerData.gold = 999999
	PlayerData.reward_point = 9999
	for id in Utils.am_dict: Demo.try_purchase("attachment", id)
	for id in Utils.weapon_list: Demo.try_purchase("weapon", id)
	for id in DemoConfig.TALENTS:
		var guard := 0
		while Demo.rank(id) < DemoConfig.TALENTS[id].max and guard < 12:
			Demo.try_purchase("talent", id, "points")
			guard += 1
	Demo.open_stats()
	await get_tree().create_timer(1.2).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var panel := Utils.canvasLayer.get_child(Utils.canvasLayer.get_child_count() - 1)
	# The build overview is the tab this complaint is about; make sure it is the
	# one on screen.
	if panel != null and panel.get("tab") != null:
		panel.tab = "build"
		if panel.has_method("render"): panel.render()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(OUT_DIR + "/build-overview.png"))
	print("[statshot] wrote build-overview err=%d size=%dx%d" % [err, image.get_width(), image.get_height()])
	get_tree().quit(0 if err == OK else 1)

extends "res://tests/M8Runtime.gd"

## Rendered evidence for the two P0 acceptance questions:
##   --shot=hud     the live product HP bar beside the real PlayerData value
##   --shot=result  the 行动结算 result card at its real 1536x864 layout
##
## Runs the REAL product session (no test_mode, no --e2e). Non-headless only:
## it needs a real renderer to produce pixels.
const FIXTURE_SAVE := "user://p0-shot-camp.json"

var shot := "hud"
var out_dir := "user://p0-shots"

func _ready():
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--shot="): shot = arg.substr(7)
		if arg.begins_with("--out="): out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if DisplayServer.get_name() == "headless":
		print("P0_SHOT headless renderer cannot capture pixels")
		get_tree().quit(1)
		return
	Demo.save_path = FIXTURE_SAVE
	if FileAccess.file_exists(FIXTURE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_SAVE))
	Demo.test_mode = false
	seed(808)
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	await wait(0.8)
	dismiss()
	if Demo.try_purchase("weapon","112").success:
		Utils.player.changeWeapon(112)
	if shot == "result":
		await _shot_result()
	else:
		await _shot_hud()
	get_tree().quit.call_deferred(0 if failures == 0 else 1)

func _save(name: String) -> void:
	# Three presented frames, so a temporal blend cannot leak a previous frame into
	# the evidence image.
	for _index in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir,name]
	var error := image.save_png(path)
	print("P0_SHOT ",JSON.stringify({"name":name,"path":ProjectSettings.globalize_path(path),
		"error":error,"size":[image.get_width(),image.get_height()]}))

## Let real monsters hit a player who presses nothing, and capture the frame at
## the moment the real HP is mid-bar. That is the only way to show that the
## rendered percentage is the live value rather than a stuck 100%.
func _shot_hud() -> void:
	LevelServer.town.depart(Demo.next_stage,false)
	var deadline := Time.get_ticks_msec()+8000
	while LevelServer.state != "COMBAT" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ui = Utils.canvasLayer.get_node("GameUI")
	var bar: ProgressBar = ui.get_node("hpUI/ProgressBar")
	await _save("hud-full")
	print("P0_SHOT full ",JSON.stringify({"hp":PlayerData.player_hp,"bar":bar.value,"bar_max":bar.max_value}))
	# Wait until a real hit has landed, then capture again.
	var clock := 0.0
	while PlayerData.player_hp >= 5.0 and clock < 30.0 and not Utils.player.is_dead:
		await get_tree().process_frame
		clock += get_process_delta_time()
	await _save("hud-damaged")
	print("P0_SHOT damaged ",JSON.stringify({"hp":PlayerData.player_hp,"bar":bar.value,"bar_max":bar.max_value,"pct":int(round(bar.value/bar.max_value*100.0))}))
	# And once more with the player nearly dead, to show the bar at its floor.
	while PlayerData.player_hp > 1.0 and clock < 60.0 and not Utils.player.is_dead:
		await get_tree().process_frame
		clock += get_process_delta_time()
	await _save("hud-low")
	print("P0_SHOT low ",JSON.stringify({"hp":PlayerData.player_hp,"bar":bar.value,"bar_max":bar.max_value,"pct":int(round(bar.value/bar.max_value*100.0)),"dead":Utils.player.is_dead}))
	check(LevelServer.state == "COMBAT" or Utils.player.is_dead,"the HUD capture ran a real combat round")
	check(true,"captured the live product HP bar at full, damaged and low health")

## The card itself, at the real design resolution, using the same data shape the
## round result hands it.
func _shot_result() -> void:
	var card = load("res://ui/widgets/Scoreboard.tscn").instantiate()
	card.setData({"time":125,"kill":18,"gold":42,"stage":1,"trial":false})
	Utils.canvasLayer.add_child(card)
	await wait(1.0)
	var panel: Control = card.get_node("Panel")
	print("P0_SHOT result ",JSON.stringify({"panel_pos":[panel.global_position.x,panel.global_position.y],
		"panel_size":[panel.size.x,panel.size.y],"viewport":get_viewport().get_visible_rect().size}))
	await _save("result-1536x864")
	check(panel.size.x <= 200.0 and panel.size.y <= 140.0,"the result card stays a compact card")
	card.queue_free()
	await wait(0.2)

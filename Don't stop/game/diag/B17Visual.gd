extends Node
# Explicit isolated export-only observation driver; never active in normal play.
var output = "user://b17-visual"
var aim_angle = 0.0
var tracking = false

func _enter_tree():
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_window().unfocusable=true
	get_window().mouse_passthrough=true
	get_window().position=Vector2i(60,60)

func _process(_delta):
	if tracking and is_instance_valid(Utils.player):
		Utils.aim_override=get_viewport().get_canvas_transform()*(Utils.player.global_position+Vector2.RIGHT.rotated(aim_angle)*100)

func wait(seconds):
	await get_tree().create_timer(seconds,true).timeout

func capture(name):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")
	if "--b17-physical" in OS.get_cmdline_user_args() and (name.begins_with("ui-weapon-") or name.ends_with("-on") or name.ends_with("-off")):
		print("B17_CAPTURE ",name)
		var started=Time.get_ticks_msec()
		while not FileAccess.file_exists(output+"/"+name+".ack") and Time.get_ticks_msec()-started<15000:
			await wait(0.05)

func _ready():
	Demo.test_mode=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--b17-output="): output=arg.substr(13)
	DirAccess.make_dir_recursive_absolute(output)
	await wait(3)
	await Smoke._enter_camp_from_title()
	await Smoke._wait_until(func(): return LevelServer.state=="CAMP",60000)
	Smoke._tour_close_panels()
	await wait(0.1)
	PlayerData.gold=999999; PlayerData.reward_point=9999
	for id in [0,112,121,116,113,120,124,6,111,114,115,122]: Demo.try_purchase("weapon",str(id))
	Demo.open_panel()
	for resolution in [Vector2i(1280,720),Vector2i(1366,768),Vector2i(1536,864),Vector2i(1920,1080)]:
		get_window().size=resolution
		for page in ["weapon","attachment","magazine","talent","stage"]:
			Demo.ui.switch_tab(page)
			if page=="weapon": Demo.ui.selection="112"; Demo.ui.render()
			await wait(0.25)
			await capture("ui-%s-%d"%[page,resolution.x])
		Smoke._tour_close_panels()
		PlayerData.clear_loadout()
		var stats=load("res://ui/StatPanel.gd").new(); Utils.canvasLayer.add_child(stats)
		for tab in ["build","player","weapon","effects","level"]:
			stats.tab=tab; stats.render(); await wait(0.15)
			await capture("empty-%s-%d"%[tab,resolution.x])
		stats.queue_free(); await wait(0.1); Demo.open_panel()
	Smoke._tour_close_panels()
	if "--b17-ui-only" in OS.get_cmdline_user_args():
		await wait(0.1); await Demo.quit_game(); return
	get_window().size=Vector2i(1366,768)
	LevelServer.town.depart(31,true); LevelServer.timerStop()
	var spawn_center=Utils.player.global_position
	tracking=true
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for id in [0,112,121,116,113,120,124,6,111,114,115,122]:
		Utils.player.changeWeapon(id)
		var gun=Utils.player.gun
		Utils.player.global_position=spawn_center
		aim_angle=0; await wait(0.3)
		for enabled in [false,true]:
			if is_instance_valid(gun.idle_visual): gun.idle_visual.aura_enabled=enabled
			await wait(0.15); await capture("gun-%d-%s"%[id,"on" if enabled else "off"])
		for direction in 8:
			aim_angle=direction*TAU/8; await wait(0.12)
			await capture("gun-%d-dir%d"%[id,direction])
		aim_angle=0
		for frame in 60:
			if frame==20: Input.action_press("right")
			if frame==40:
				Input.action_release("right"); Demo.fire_released=true; Utils.set_gameplay_mouse_mode(); Input.action_press("shoot")
			await wait(0.1)
			await capture("motion-%d-%03d"%[id,frame])
		Input.action_release("right"); Input.action_release("shoot"); gun.cancel_actions()
		print("B17_VISUAL weapon=",id," viewport=",get_viewport().get_visible_rect().size)
	Smoke._tour_close_panels(); LevelServer.return_to_camp(); await wait(0.2)
	LevelServer.town.depart(1,true); LevelServer.timerStop()
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for id in [112,121,116,113,120,124,6,111,114,115,122]:
		Utils.player.changeWeapon(id); aim_angle=0; await wait(0.2)
		for enabled in [false,true]:
			Utils.player.gun.idle_visual.aura_enabled=enabled
			await wait(0.1); await capture("normal-%d-%s"%[id,"on" if enabled else "off"])
	tracking=false; LevelServer.return_to_camp()
	await Demo.quit_game()

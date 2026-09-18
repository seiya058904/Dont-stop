extends "res://tests/M3Weapons.gd"
## B12 visual acceptance. MUST run windowed (a headless run has no render target):
##   godot --path . --rendering-method gl_compatibility --quit-after 40000 res://tests/B12Visual.tscn
## gl_compatibility on desktop is the same renderer the Web build uses
## (project.godot sets rendering_method.web = gl_compatibility).
## Captures, into docs/iteration/evidence/b12/visual/:
##   * the camp shop listing filtered to each of the five qualities (quality names on cards)
##   * the detail badge for one weapon per quality (quality name + type + price, no Tier text)
##   * one representative weapon per quality actually firing at a live target,
##     including both 史诗 (plasma howitzer, delayed AoE) and 传说 (rotary) representatives.

const OUT := "res://docs/iteration/evidence/b12/visual"
const FIRE_IDS := [1, 7, 118, 114, 124]  # 普通 / 精良 / 稀有 / 史诗 / 传说

var view: SubViewport

func snap(name: String):
	await RenderingServer.frame_post_draw
	# The camp panel lives on Utils.canvasLayer inside the Main scene, which this test
	# instantiates inside the SubViewport - so the UI is captured from THERE, not from
	# the root viewport (M9Catalog's shop capture works the same way).
	var picture: Image = view.get_texture().get_image()
	picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	var err: int = picture.save_png("%s/%s.png" % [OUT, name])
	print("B12_VISUAL captured ", name, " err=", err)

func _ready():
	Demo.test_mode = true
	if DisplayServer.get_name() == "headless":
		print("B12_VISUAL skipped: headless has no render target (run windowed)")
		await Demo.quit_game(); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var sv = SubViewport.new(); view = sv; sv.size = Vector2i(410,230); sv.world_2d = get_viewport().world_2d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(sv)
	sv.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	for id in FIRE_IDS: Demo.try_purchase("weapon",str(id))
	# --- shop: one capture per quality filter + full listing ------------------------------
	Demo.open_panel(); Demo.ui.switch_tab("weapon"); await wait(0.3)
	var panel = Demo.ui
	RenderingServer.force_draw(false); await snap("shop-all")
	for t in range(1,6):
		panel.tier_filter = t; panel.render(); await wait(0.15)
		RenderingServer.force_draw(false); await snap("shop-quality-%d" % t)
	# --- detail badge per quality ---------------------------------------------------------
	for id in FIRE_IDS:
		panel.tier_filter = 0; panel.search_text = ""; panel.search_box.text = ""
		panel.selection = str(id); panel.render(); await wait(0.15)
		RenderingServer.force_draw(false); await snap("detail-quality-%d-id-%d" % [WeaponCatalog.tier(id), id])
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
	await wait(0.2)
	# --- fire one representative per quality ----------------------------------------------
	LevelServer.town.depart(6,true); LevelServer.timerStop()
	for camera in get_tree().get_nodes_in_group("camera"): camera.enabled = false
	var capture_camera = Camera2D.new(); view.add_child(capture_camera)
	capture_camera.global_position = Utils.player.global_position; capture_camera.make_current()
	await wait(1.0)
	for id in FIRE_IDS:
		var gun = PlayerData.player_weapon_list[id]; Utils.player.changeWeapon(id)
		gun.set_process(false); gun.cancel_actions()
		LevelServer.state = "COMBAT"
		var point = LevelServer.town.spawn_near(Utils.player.global_position,50,80)
		for attempt in 30:
			if Combat.clear_line(Utils.player.global_position,point): break
			point = LevelServer.town.spawn_near(Utils.player.global_position,50,80)
		var target = enemy(point,10000)
		var warning = load("res://game/monster/HostileZone.gd").new(); warning.damage=0; warning.warning=5; warning.radius=30; warning.position=point; add_child(warning)
		await wait(0.3)
		Utils.aim_override = get_viewport().get_canvas_transform()*(point-Vector2(0,8))
		gun.look_at(point-Vector2(0,8)); gun.direction = gun.gun_tip.global_position.direction_to(point-Vector2(0,8))
		gun._shoot()
		# Delayed AoE (howitzer/gravity) needs the travel+detonation window on screen.
		await wait(0.4 if "explosive" in DemoConfig.weapon_tags(id) else 0.06)
		await RenderingServer.frame_post_draw
		var picture: Image = view.get_texture().get_image()
		picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
		picture.save_png("%s/fire-quality-%d-id-%d.png" % [OUT, WeaponCatalog.tier(id), id])
		print("B12_VISUAL fired quality=",WeaponCatalog.tier(id)," id=",id)
		gun.cancel_actions(); await clean()
		Utils.aim_override = null
	await Demo.quit_game()

extends "res://tests/M8Runtime.gd"
var scenario = "normal"
func _ready():
	await boot(); configure(124)
	for arg in OS.get_cmdline_user_args():
		if arg in ["normal","late","boss","projectile","telegraph","particle","boss-barrage"]: scenario = arg
	LevelServer.town.depart(29,true); LevelServer.timerStop()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000
	var counts = {"normal":12,"late":50,"boss":0,"projectile":150,"telegraph":24,"particle":30,"boss-barrage":0}
	var root = LevelServer.town.monster_root
	for i in counts[scenario]:
		var point = LevelServer.town.spawn_near(Utils.player.global_position,80,200)
		if point!=Vector2.INF: M5Content.spawn(M5Content.ENEMIES.keys()[i%12],root,point)
	if scenario=="boss": M5Content.spawn("B03",root,Utils.player.global_position+Vector2(140,0))
	var barrage_owner = null
	if scenario=="boss-barrage": barrage_owner = M5Content.spawn("B02",root,Utils.player.global_position+Vector2(140,0))
	var frames = []; var peak = 0; var effects_peak = 0; var start = Time.get_ticks_usec(); var previous = start; var clock = 0.0
	var zones_peak = 0; var replenishments = 0
	while Time.get_ticks_usec()-start<20000000:
		await get_tree().process_frame
		var now = Time.get_ticks_usec(); var delta = (now-previous)/1000000.0; previous = now
		if now-start>3000000: frames.append(delta*1000.0)
		clock += delta
		if clock<0.2: continue
		clock = 0
		var nodes = get_tree().get_nodes_in_group("combat_transient")
		peak = maxi(peak,nodes.size()); effects_peak = maxi(effects_peak,get_tree().get_nodes_in_group("hostile_vfx").size())
		if scenario=="boss-barrage":
			var enemy_count = nodes.filter(func(n): return n.get_script()==load("res://game/monster/EnemyShot.gd")).size()
			for i in maxi(0,160-enemy_count): barrage_owner.shot(Vector2.RIGHT.rotated(i*TAU/160),100)
		if scenario=="projectile":
			var bullets = nodes.filter(func(n): return n is Bullet).size()
			for i in maxi(0,400-bullets):
				var bullet = load("res://game/bullets/SmpBullet.tscn").instantiate()
				bullet.context = {"damage":0.0,"depth":1,"epoch":LevelServer.epoch}; bullet.speed = 90; root.add_child(bullet)
				bullet.global_position = Utils.player.global_position+Vector2(randf_range(-170,170),randf_range(-90,90)); bullet.rotation = randf()*TAU; bullet.fire()
		if scenario=="telegraph":
			for i in maxi(0,60-get_tree().get_nodes_in_group("hostile_zone").size()):
				var zone = load("res://game/monster/HostileZone.gd").new(); zone.mode = ["circle","line","cone"][i%3]; zone.warning = 0.8; zone.duration = 0.3; zone.damage = 0
				zone.position = Utils.player.global_position+Vector2(randf_range(-150,150),randf_range(-80,80)); zone.direction = Vector2.RIGHT.rotated(randf()*TAU); zone.radius = 35; zone.length=140; add_child(zone)
				replenishments += 1
			zones_peak=maxi(zones_peak,get_tree().get_nodes_in_group("hostile_zone").size())
		if scenario=="particle":
			for i in 12:
				var point = Utils.player.global_position+Vector2(randf_range(-140,140),randf_range(-70,70))
				Combat.explosion(point,30,0,null,1)
				Utils.player.gun._shootAnim()
	frames.sort()
	var row = {"scenario":scenario,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"frames":frames.size(),"p50":frames[int(frames.size()*0.5)],"p95":frames[int(frames.size()*0.95)],"p99":frames[int(frames.size()*0.99)],"max":frames.back(),"transients_peak":peak,"hostile_vfx_peak":effects_peak,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if "--telegraph-profile" in OS.get_cmdline_user_args():
		print("M8 TELEGRAPH PROFILE ",JSON.stringify(load("res://game/monster/HostileZone.gd").profile_snapshot()))
	row.telegraph_target=60 if scenario=="telegraph" else 0; row.zones_peak=zones_peak; row.replenishments=replenishments
	row.mouse_mode=Input.mouse_mode; row.unfocusable=get_window().unfocusable; row.mouse_passthrough=get_window().mouse_passthrough
	row.viewport_draw_calls=RenderingServer.viewport_get_render_info(play_view.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	row.global_draw_calls=row.draw_calls
	row.draw_calls=RenderingServer.viewport_get_render_info(play_view.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	if DisplayServer.get_name()!="headless": check(row.draw_calls>0,"actual game viewport canvas rendered")
	if DisplayServer.get_name()!="headless": check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and get_window().unfocusable and get_window().mouse_passthrough,"render window cannot confine mouse or take focus")
	if scenario=="telegraph": check(zones_peak>=60,"unchanged 60 telegraph pressure input")
	print("M9 PERF ",JSON.stringify(row)); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty() and get_tree().get_nodes_in_group("monsters").is_empty(),"performance fixture cleanup")
	print("M9 PERF SUMMARY checks=",checks," failures=",failures)
	await Demo.quit_game()

extends "res://tests/M8Runtime.gd"

var output: String
func capture(name: String):
	await wait(0.08)
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var frame = play_view.get_texture().get_image()
	frame.save_png(output+"/"+name+".png")
	return frame

func _ready():
	await boot()
	dismiss()
	output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	var observer = Camera2D.new()
	play_view.add_child(observer)
	observer.global_position = Utils.player.global_position
	observer.make_current()
	configure(124,false)
	var ui = Utils.canvasLayer.get_node("GameUI")
	await wait(1.3)
	for amount in [100,60,1,0]:
		Utils.player.gun.bullets_count = amount
		ui.onWeaponBulletsChange(amount,100)
		await wait(0.25) # Let the original spent-segment flash finish before a static ratio view.
		await capture("ammo-"+str(amount))
	Utils.player.gun.reload_ammo()
	await capture("ammo-reload")
	Utils.player.gun.cancel_actions()
	LevelServer.state = "CAMP"
	Demo.unequip_weapon()
	await capture("ammo-unarmed")
	LevelServer.state = "COMBAT"
	var zone = load("res://game/monster/HostileZone.gd").new()
	zone.mode = "line"
	zone.style = "beam"
	zone.world_point = Utils.player.global_position+Vector2(-80,-35)
	zone.length = 160
	zone.warning = 0.6
	zone.duration = 1
	zone.damage = 1
	add_child(zone)
	zone.set_physics_process(false)
	zone.profiling = true
	zone.fair_gate = true
	zone.step(0.8)
	check(not zone.activated,"fair gate extends warning after nominal warning time")
	check(zone.hit_count == 0,"extended warning deals no damage")
	var waiting_frame = await capture("zone-waiting")
	zone.visible_warning = zone.FAIR_VISIBLE
	zone.step(0.01)
	check(zone.activated,"actual gate release activates zone")
	var active_frame = await capture("zone-active")
	check(waiting_frame.get_pixel(280,80).get_luminance() < active_frame.get_pixel(280,80).get_luminance(),"extended warning stays visually distinct from real firing")
	var activation_draws = zone.profile_snapshot().redraw_requests
	zone.step(0.01)
	check(zone.profile_snapshot().redraw_requests == activation_draws,"frozen active footprint does not redraw the activation edge twice")
	zone.queue_free()
	await wait(0.1)
	for role in ["B01","B02","B03","B04"]:
		var ultimate = load("res://game/monster/BossUltimate.gd").new()
		ultimate.role = role
		ultimate.position = Utils.player.global_position+Vector2(50,-20)
		add_child(ultimate)
		ultimate.set_physics_process(false)
		ultimate.elapsed = ultimate.warning+0.2
		ultimate.queue_redraw()
		await capture(role+"-waiting")
		ultimate.activated = true
		ultimate.queue_redraw()
		await capture(role+"-active")
		ultimate.queue_free()
		await wait(0.05)
	# Exercise the real feedback channel with an explicitly configured status label.
	# This observes text rendering, not a claim that a shield proc occurred here.
	Utils.showHitLabel("护盾",Utils.player)
	Utils.showHitLabelMore(0.875,Utils.player,Vector2(28,0))
	await wait(0.2)
	check(get_tree().get_nodes_in_group("damage_labels").any(func(label): return label.text == "护盾"),"production feedback channel preserves shield status text")
	await capture("status-shield-text")
	LevelServer.return_to_camp()
	await wait(0.1)
	LevelServer.town.depart(6,true)
	observer.global_position = Utils.player.global_position
	await wait(0.3)
	Utils.showHitLabel("护盾",Utils.player)
	Utils.showHitLabelMore(0.875,Utils.player,Vector2(28,0))
	await wait(0.2)
	await capture("status-text-dark-floor")
	print("PRESENTATION_STATES checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

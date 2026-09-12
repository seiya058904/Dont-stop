extends "res://tests/M3Weapons.gd"
var samples = []
func _ready():
	Demo.test_mode = true
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.5)
	for id in [6,117,118,120,121,122,124]: Demo.try_purchase("weapon",str(id))
	for cycle in 12:
		var id = [6,117,118,120,121,122,124][cycle%7]
		LevelServer.state = "COMBAT"
		Utils.player.global_position = origin-Vector2(100,0)
		var target = enemy(origin+Vector2(60,8),1000)
		var gun = PlayerData.player_weapon_list[id]; aim(gun)
		await wait(0.1)
		for burst in 8:
			if id == 6: gun.openFire()
			else: gun._shoot()
			await wait(0.1)
		await wait(0.8)
		check(target.HP < 1000,"GPU actual mechanism hit "+str(id))
		LevelServer.return_to_camp()
		for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
		await wait(2.0)
		var row = {"cycle":cycle,"enemies":get_tree().get_nodes_in_group("monsters").size(),"transients":get_tree().get_nodes_in_group("combat_transient").size(),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_memory":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
		samples.append(row); print("GPU CLEANUP ",JSON.stringify(row))
		check(row.enemies == 0 and row.transients == 0 and row.orphans == 0,"GPU camp cleanup empty")
	var result = {"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"samples":samples,"checks":checks,"failures":failures}
	var file = FileAccess.open("res://docs/iteration/evidence/m7/regression-artifacts/gpu-cleanup.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("M6 GPU SUMMARY checks=",checks," failures=",failures)
	await Demo.quit_game()

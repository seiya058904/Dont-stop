extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	configure(112,true)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	B11Probe.enabled = true
	Demo.kill_stacks = DemoConfig.TALENTS.T10.stacks
	Demo.refresh()
	var expected = {}
	for id in PlayerData.player_weapon_list:
		expected[id] = PlayerData.player_weapon_list[id].effective.duplicate(true)
	var before = B11Probe.refresh_calls
	var start = Time.get_ticks_usec()
	for i in 200: Demo.on_kill({"training":false},{"native_attack":false})
	var calls = B11Probe.refresh_calls-before
	print("B18_REFRESH ",JSON.stringify({"kills":200,"refreshes":calls,"usec":Time.get_ticks_usec()-start,"weapons":expected.size()}))
	for id in expected: check(expected[id]==PlayerData.player_weapon_list[id].effective,"capped kill preserves weapon "+str(id))
	check(Demo.stack_time==DemoConfig.TALENTS.T10.seconds,"capped kill renews duration")
	if not "--baseline" in OS.get_cmdline_user_args(): check(calls==0,"capped kills do not recompute weapons")
	Demo.kill_stacks = 0
	before = B11Probe.refresh_calls
	Demo.on_kill({"training":false},{"native_attack":false})
	check(Demo.kill_stacks==1 and B11Probe.refresh_calls==before+1,"first stack recalculates")
	Demo.stack_time = 0.001
	Demo._process(0.01)
	check(Demo.kill_stacks==0,"expiry clears stack")
	if not "--baseline" in OS.get_cmdline_user_args():
		var script = load("res://game/monster/EnemyShot.gd")
		for cycle in 10:
			var pellets = []
			for i in script.CAPACITY+1:
				var pellet = script.new(); add_child(pellet); pellet.set_physics_process(false); pellets.append(pellet)
			check(script.live_count==script.CAPACITY,"capacity refuses overflow cycle "+str(cycle))
			for pellet in pellets:
				if is_instance_valid(pellet): pellet.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
			check(script.live_count==0 and get_tree().get_nodes_in_group("enemy_projectiles").is_empty(),"counter and group drain cycle "+str(cycle))
		var reentry = script.new(); add_child(reentry); reentry.set_physics_process(false)
		remove_child(reentry); check(script.live_count==0,"detach decrements")
		add_child(reentry); check(script.live_count==1,"reattach increments")
		reentry.free(); check(script.live_count==0,"immediate free decrements")
	print("B18_PERFORMANCE checks=",checks," failures=",failures)
	await Demo.quit_game()

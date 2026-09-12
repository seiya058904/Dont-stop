extends "res://tests/M3Weapons.gd"
# Representative mechanism pairs, not an exhaustive all-equipment product.
const CASES = [[111,111,"T13"],[113,118,"T12"],[115,113,"T17"],[116,115,"T15"],[119,121,"T16"],[120,123,"T23"],[117,119,"T15"],[118,118,"T13"],[124,124,"T11"],[122,114,"T18"],[121,121,"T16"],[112,122,"T23"]]
func _ready():
	Demo.test_mode = true
	seed(4434)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	for triple in CASES:
		var gun = PlayerData.player_weapon_list[triple[0]]
		aim(gun)
		var am = PlayerData.player_am_list.values().filter(func(a): return a.am_id == triple[1])[0]
		check(gun.addAttachMent(am),"pair compatible "+str(triple))
		Demo.talents = {triple[2]:DemoConfig.TALENTS[triple[2]].max}
		Demo.talent_payments.clear()
		Demo.refresh()
		LevelServer.state = "COMBAT"
		for i in 4: enemy(origin+Vector2(35+i*18,8),3.0)
		await wait(0.06)
		var hits = Combat.damage_events
		gun._shoot()
		await wait(1.6)
		check(Combat.damage_events > hits,"pair real damage "+str(triple))
		check(Combat.damage_events-hits < 100 and Combat.max_depth_seen <= 2,"pair finite derivation "+str(triple))
		LevelServer.return_to_camp()
		await wait(0.4)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"pair camp cleanup "+str(triple))
		gun.removeAttachMent(am)
		await clean()
	# All three secondary families together at legal maxima, including forced fixture crit.
	LevelServer.state = "COMBAT"
	for id in DemoConfig.TALENTS: Demo.talents[id] = DemoConfig.TALENTS[id].max
	Demo.refresh()
	var gun = PlayerData.player_weapon_list[118]
	aim(gun)
	for i in 12: enemy(origin+Vector2(35+i%4*16,i/4*16+8),4.0)
	await wait(0.06)
	var hits = Combat.damage_events
	gun._shoot()
	await wait(3.2)
	check(Combat.damage_events > hits and Combat.damage_events-hits < 200 and Combat.max_depth_seen <= 2,"max legal split arc burn echo explosion finite")
	LevelServer.return_to_camp()
	await wait(1.0)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"max legal combo no cross-round attacks")
	print("M4 COMBINATIONS SUMMARY checks=",checks," failures=",failures," cases=",CASES.size()," max_depth=",Combat.max_depth_seen)
	get_tree().quit.call_deferred(1 if failures else 0)

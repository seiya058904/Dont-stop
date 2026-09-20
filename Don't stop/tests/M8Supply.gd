extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	for gun in PlayerData.player_weapon_list.values():
		aim(gun); gun.set_physics_process(false); PlayerData.reserve_magazines = 3
		for cycle in 3:
			gun.bullets_count = 1 if gun.bullets_max_count>1 else 0
			gun.reload_ammo(); await wait(gun.effective.reload+0.05)
			check(gun.bullets_count==gun.bullets_max_count and PlayerData.reserve_magazines==2-cycle,"full/partial whole-mag reload "+str(gun.weapon_id))
		gun.bullets_count = 0; gun.reload_ammo(); await wait(0.03)
		check(not gun.is_reloading and gun.bullets_count==0,"zero magazines cannot reload "+str(gun.weapon_id))
		PlayerData.reserve_magazines = 2; gun.reload_ammo(); gun.cancel_actions(); await wait(gun.effective.reload+0.05)
		check(PlayerData.reserve_magazines==2 and gun.bullets_count==0,"cancelled reload spends nothing "+str(gun.weapon_id))
		check(gun.effective==EffectiveStats.calculate(gun) and Demo.owned_global_upgrades.size()==24,"switch keeps all buffs "+str(gun.weapon_id))
	LevelServer.state = "COMBAT"
	var blast_target = enemy(origin+Vector2(75,-10),1000)
	Demo.grenade_cooldown = 0
	Combat.hit(blast_target,Utils.player.gun.shot_context())
	check(Demo.grenade_cooldown > 0,"global automatic blast works on current gun")
	check(not Demo.fire_global_grenade(origin),"global grenade cooldown prevents repeats")
	LevelServer.return_to_camp(); await wait(0.2)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"global grenade leaves with combat")
	print("M8 SUPPLY SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

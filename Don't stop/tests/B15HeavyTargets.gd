extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position=origin-Vector2(20,0)
	var rows=[]
	for key in Utils.weapon_list:
		for target_kind in ["elite","boss"]:
			await clean(); configure(int(key))
			var gun=Utils.player.gun
			PlayerData.player_level=1; PlayerData.player_exp=0
			Demo.talents={}; Demo.owned_global_upgrades=[]; Demo.refresh(); gun.updateGun()
			var target=enemy(origin+Vector2(55,8),100000)
			target.is_elite=target_kind=="elite"; target.is_boss=target_kind=="boss"
			target.knockback_def=100000
			target.training=false
			target.set_physics_process(false)
			await wait(0.08); LevelServer.state="COMBAT"
			var start=Time.get_ticks_msec(); var last=start
			while Time.get_ticks_msec()-start<3500:
				var now=Time.get_ticks_msec(); var dt=(now-last)/1000.0; last=now
				fire_at(target.global_position-Vector2(0,8),dt)
				if int(key)==6: gun._physics_process(dt)
				await wait(0.01)
			gun.cancel_actions()
			var amount=100000-target.HP
			check(amount>0,"actual fire damages %s flag target %s"%[target_kind,key])
			rows.append({"id":int(key),"kind":target_kind,"seconds":3.5,"damage":amount,"method":"stationary high-HP target with elite/boss flag; not a real Boss fight"})
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b15-heavy-targets.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("B15 HEAVY checks=",checks," failures=",failures)
	await clean(); get_tree().quit(1 if failures else 0)

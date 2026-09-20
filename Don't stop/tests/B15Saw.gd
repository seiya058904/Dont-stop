extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position=origin-Vector2(20,0)
	configure(122)
	Demo.talents={}; Demo.owned_global_upgrades=[]; Demo.refresh()
	var gun=Utils.player.gun
	gun.updateGun(); gun.bullets_count=gun.bullets_max_count
	var target=enemy(origin+Vector2(55,8),100000)
	target.knockback_def=100000; target.set_physics_process(false)
	await wait(0.1); LevelServer.state="COMBAT"
	var times=[]; var reloads=0; var previous_reload=false
	var start=Time.get_ticks_msec(); var previous=start
	shots_fired=0
	while times.size()<48 and Time.get_ticks_msec()-start<16000:
		var now=Time.get_ticks_msec(); var before=shots_fired
		fire_at(target.global_position-Vector2(0,8),(now-previous)/1000.0); previous=now
		if shots_fired>before: times.append((now-start)/1000.0)
		if gun.is_reloading and not previous_reload: reloads+=1
		previous_reload=gun.is_reloading
		await wait(0.005)
	check(is_equal_approx(gun.timer.wait_time,0.25),"saw authoritative shot timer is 4 per second")
	check(times.size()>=24 and times[23]-times[0]<6.2,"saw fires real full 24-round magazine within 6.2 seconds")
	check(times.size()==48 and reloads>=1 and times[-1]<14.7,"saw reloads and fires second real magazine within 14.7 seconds")
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b15-saw.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"times":times,"reloads":reloads,"damage":100000-target.HP},"\t")); file.close()
	gun.cancel_actions(); await clean()
	get_tree().quit(1 if failures else 0)

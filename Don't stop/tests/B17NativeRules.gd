extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(0)
	var gun=Utils.player.gun
	var battery=RewardServer.reward_list["9"].instantiate(); RewardServer.addReward(battery)
	var sickle=RewardServer.reward_list["8"].instantiate(); RewardServer.addReward(sickle)
	Demo.talents={"T10":1,"T11":1,"T19":1,"T24":1}; Demo.refresh()
	for native in [true,false]:
		LevelServer.state="COMBAT"
		Demo.ammo_kills=0; Demo.kill_stacks=0; Demo.heal_cooldown=0
		Demo.talent_cooldowns={"T19":6.0}; Demo.shield_age=3
		gun.bullets_count=0; battery.is_time_out=true
		PlayerData.player_hp=2; PlayerData.reserve_magazines=10
		for i in 5:
			var target=enemy(origin+Vector2(20*i,80),0.1)
			Combat.hit(target,{"damage":1.0,"crit":1.0,"depth":1,"native_attack":native,"epoch":LevelServer.epoch,"gun":gun,"refill":1})
		check(battery.is_time_out and sickle.kill_count==0,"depth-one never enters direct-only prototype hooks native="+str(native))
		check(PlayerData.reserve_magazines==(11 if native else 10),"native qualification controls T11 actual reserve gain")
		check(is_equal_approx(PlayerData.player_hp,2.2 if native else 2.0),"native qualification controls T24 actual healing")
		check(gun.bullets_count==(2 if native else 0),"native qualification controls A124 ceil 8-percent refill")
		check(is_equal_approx(Demo.cooldown("T19"),4.25 if native else 6.0),"native qualification controls shield cooldown reduction")
		check(Demo.kill_stacks==5,"T10 deliberately counts both native and derived kills")
		await clean()
	check(HellMode.has_fog(30) and not HellMode.is_hell(30),"stage30 visual fog does not activate Hell gameplay multipliers")
	print("B17 NATIVE RULES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

extends "res://tests/M8Runtime.gd"

func clear_rewards():
	for reward in Utils.player.reward_root.get_children(): reward.free()
	Demo.talents.clear(); Demo.owned_global_upgrades.clear(); Demo.refresh()
	PlayerData.player_hp_max=1000; PlayerData.player_hp=500

func give(id):
	RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
	for reward in Utils.player.reward_root.get_children():
		if reward.id==id: return reward
	return null

func kills(count):
	for i in count:
		var target=enemy(origin+Vector2(i%10*12,50),0.1)
		Combat.hit(target,{"damage":1.0,"crit":0.0,"depth":0,"epoch":LevelServer.epoch})

func _ready():
	await boot(); configure(0); LevelServer.state="COMBAT"
	clear_rewards()
	var gold=PlayerData.gold
	give(0); check(PlayerData.gold==gold+10,"R0 one-off gold resource +10")
	give(1); check(PlayerData.player_hp==PlayerData.player_hp_max,"R1 actual full heal")
	clear_rewards(); give(17)
	Utils.player.onHit(2); var hp=PlayerData.player_hp; Utils.player.onHit(2)
	check(is_equal_approx(hp-PlayerData.player_hp,1.6),"R17 armed ordinary damage actually reduced 20 percent")
	clear_rewards(); give(19)
	PlayerData.player_hp_max=20; PlayerData.player_hp=6
	Utils.player.onHit(1)
	check(is_equal_approx(PlayerData.player_hp,6),"R19 emergency event restores one actual HP")
	clear_rewards(); give(18)
	hp=PlayerData.player_hp
	kills(12)
	check(is_equal_approx(PlayerData.player_hp,hp+0.5),"R18 twelve direct kills restore 0.5 actual HP")
	await clean(); LevelServer.state="COMBAT"
	clear_rewards(); give(21)
	var reserve=PlayerData.reserve_magazines
	kills(15)
	check(PlayerData.reserve_magazines==reserve+1,"R21 fifteen direct kills add one reserve magazine")
	await clean(); LevelServer.state="COMBAT"
	clear_rewards(); give(8)
	var rate=PlayerData.player_fire_rate
	kills(3)
	check(is_equal_approx(PlayerData.player_fire_rate,rate+0.2),"R8 three actual kills activate fire-rate buff")
	await clean(); LevelServer.state="COMBAT"
	clear_rewards(); give(10)
	hp=PlayerData.player_hp_max
	var old_level=PlayerData.player_level
	kills(101)
	var level_hp=(PlayerData.player_level-old_level)*PlayerData.PROGRESSION.HP_PER_LEVEL
	check(is_equal_approx(PlayerData.player_hp_max,hp+10+level_hp),"R10 actual kill growth caps at one hundred events apart from level HP")
	await clean(); LevelServer.state="COMBAT"
	clear_rewards(); var battery=give(9)
	battery.is_time_out=true
	var target=enemy(origin,100)
	Combat.hit(target,{"damage":10.0,"depth":1,"native_attack":true,"epoch":LevelServer.epoch})
	check(battery.is_time_out and is_equal_approx(target.HP,90),"native depth-one hit deliberately does not consume direct-only battery")
	Combat.hit(target,{"damage":10.0,"depth":0,"epoch":LevelServer.epoch})
	check(not battery.is_time_out and is_equal_approx(target.HP,75),"depth-zero consumes battery with actual 15 HP delta")
	await clean()
	print("B17 RESOURCES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

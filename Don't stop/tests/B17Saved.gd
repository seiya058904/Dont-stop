extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(0)
	var data=Demo.snapshot()
	var before=EffectiveStats.calculate(Utils.player.gun,null,data)
	PlayerData.base_magazine_count=4; PlayerData.base_bullet_damage=7
	PlayerData.base_reload_speed=0.7; PlayerData.base_aim_enh=80
	Demo.kill_stacks=5; PlayerData.player_fire_rate=2
	check(EffectiveStats.calculate(Utils.player.gun,null,data)==before,"saved calculations ignore live base fields and temporary stacks")
	check(CampSnapshot.validate(data),"saved validation unaffected by live character")
	PlayerData.base_magazine_count=0; PlayerData.base_bullet_damage=0
	PlayerData.base_reload_speed=0; PlayerData.base_aim_enh=0
	Demo.kill_stacks=0; PlayerData.player_fire_rate=1
	data.legacy=[]; data.legacy_state={}; data.hp_max=41; data.hp=31
	for id in ["2","3","5","6","7","9","11"]:
		for count in 8: data.legacy.append(id)
	check(CampSnapshot.validate(data),"historical over-cap purchases remain valid")
	Demo.save_path="user://b17-historical-isolated.json"
	check(Demo.save_store.save(Demo.save_path,data).success and Demo.load_camp(),"historical file restores through real load path")
	for id in [2,3,5,6,7,9,11]:
		check(Demo.purchases.count(str(id))==8 and RewardServer.rank(id)==8,"historical retained ownership and rank "+str(id))
	check(PlayerData.player_hp_max==41 and PlayerData.player_hp==31,"restore does not replay or discard historical HP")
	var gold=PlayerData.gold
	check(not Demo.try_purchase("legacy","9","gold").success and PlayerData.gold==gold,"historical over-cap cannot repurchase")
	print("B17 SAVED checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

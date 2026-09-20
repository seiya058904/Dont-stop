extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	configure(0)
	var gun = Utils.player.gun
	aim(gun)
	Demo.owned_global_upgrades = ["9"]
	gun.updateGun()
	var target = enemy(origin+Vector2(50,8),10000)
	var neighbor = enemy(origin+Vector2(65,8),10000)
	await wait(0.1)
	LevelServer.state = "COMBAT"
	var context = gun.shot_context()
	context.crit = 0
	Combat.hit(target,context)
	check(neighbor.HP < 10000,"A9 actual hit automatically damages nearby enemy")
	var hp = neighbor.HP
	Combat.hit(target,context)
	check(neighbor.HP == hp,"A9 shares cooldown across hits")
	Demo.talents = {"T19":1,"T24":3,"T11":1}
	Demo.talent_cooldowns.T19 = 6.0
	Demo.heal_cooldown = 0
	PlayerData.player_hp = 1
	var native = gun.damage_context(1)
	native.native_attack = true
	Demo.on_kill(target,native)
	check(PlayerData.player_hp > 1,"native branch kill heals")
	check(Demo.cooldown("T19") < 6.0,"native kill charges shield recovery")
	check(Demo.ammo_kills == 1,"native branch counts for reserve magazines")
	check(DemoConfig.talent_quality("T09") == 3 and DemoConfig.TALENTS.T09.max == 3,"T09 legendary keeps three ranks")
	check(DemoConfig.talent_gold_price("T09",3) > DemoConfig.talent_gold_price("T09",1),"T09 has per-rank prices")
	await clean()
	print("B16 GROWTH checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

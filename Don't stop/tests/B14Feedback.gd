extends "res://tests/M8Runtime.gd"

func count_style(style):
	return get_tree().get_nodes_in_group("hostile_vfx").filter(func(n):return n.style==style).size()

func _ready():
	await boot();configure(0)
	Demo.talents={"T19":1};Demo.talent_cooldowns={};Demo.owned_global_upgrades=[]
	LevelServer.state="COMBAT"
	var hp=PlayerData.player_hp
	Utils.player.onHit(1,null,1,"b14-test")
	check(PlayerData.player_hp==hp and count_style("shield")==1,"actual shield block emits one fracture without HP damage")
	Utils.player.onHit(1,null,1,"b14-test")
	check(PlayerData.player_hp<hp and count_style("shield")==1,"cooldown hit cannot fake a second shield fracture")
	await clean()
	Demo.talents={"T24":3};Demo.heal_cooldown=0;Demo.talent_cooldowns={}
	var gun=Utils.player.gun
	var dead=enemy(origin,1)
	gun.bullets_count=gun.bullets_max_count-2
	PlayerData.player_hp=PlayerData.player_hp_max-1
	Demo.on_kill(dead,{"depth":0,"gun":gun,"refill":1})
	check(count_style("refill")==1 and count_style("heal")==1,"real ammo and HP increases emit distinct feedback")
	await clean();dead=enemy(origin,1)
	Demo.heal_cooldown=0;Demo.talent_cooldowns={}
	gun.bullets_count=gun.bullets_max_count;PlayerData.player_hp=PlayerData.player_hp_max
	Demo.on_kill(dead,{"depth":0,"gun":gun,"refill":1})
	check(count_style("refill")==0 and count_style("heal")==0,"full ammo/full HP cannot show fake refill or treatment")
	Demo.talents={"T12":1};gun.updateGun();gun.bullets_count=gun.bullets_max_count-1
	PlayerData.reserve_magazines=10;gun.reload_ammo();await wait(gun.effective.reload+0.15)
	var status=load("res://game/config/CombatStatus.gd")
	check(status.entries().any(func(r):return r.name=="首发"),"real reload exposes first-shot ready status")
	gun.shot_context()
	check(not status.entries().any(func(r):return r.name=="首发"),"consumed first shot removes ready status")
	print("B14_FEEDBACK_CHECKS ",checks," FAILURES ",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

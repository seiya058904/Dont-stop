extends "res://tests/M8Runtime.gd"

func coin(at):
	var item = load("res://game/items/Gold.tscn").instantiate()
	add_child(item)
	item.global_position = at
	return item

func _ready():
	await boot()
	Utils.player.set_physics_process(false)
	Utils.player.set_process(false)
	Utils.player.global_position = origin
	LevelServer.state = "COMBAT"
	Demo.talents = {"T09":1}
	var before = PlayerData.gold
	var item = coin(origin+Vector2(100,0))
	await wait(0.25)
	check(is_instance_valid(item) and item.global_position.x < origin.x+100,"coin visibly moves before collection")
	check(PlayerData.gold == before,"no money at attraction start")
	get_tree().paused = true
	var frozen = item.global_position
	await wait(0.2)
	check(item.global_position == frozen and PlayerData.gold == before,"pause freezes flight and money")
	get_tree().paused = false
	await wait(0.8)
	check(PlayerData.gold == before+1,"arrival credits exactly once")
	var barrier = wall(origin+Vector2(50,0),Vector2(6,160))
	await wait(0.1)
	item = coin(origin+Vector2(100,0))
	await wait(0.5)
	check(item.global_position == origin+Vector2(100,0) and PlayerData.gold == before+1,"wall blocks attraction and income")
	barrier.queue_free(); item.queue_free()
	await wait(0.1)
	before = PlayerData.gold
	for i in 100: coin(origin+Vector2(80+(i%10)*2,(i/10)*2))
	await wait(2.5)
	check(PlayerData.gold == before+100,"100 coins retain exact total through active budget")
	check(load("res://game/items/Gold.gd").active_coins == 0,"no active attraction slots leaked")
	for rank in [1,2,3]:
		Demo.talents.T09 = rank
		await get_tree().physics_frame
		check(is_equal_approx(RewardServer.coin_radius(),[120.0,180.0,240.0][rank-1]),"rank radius "+str(rank))
	PlayerData.player_hp = PlayerData.player_hp_max
	var pack = load("res://game/items/HpPack.gd").new()
	pack.hp = 2
	add_child(pack); pack.global_position = origin
	pack._on_area_2d_body_entered(Utils.player)
	check(not pack.collected,"full health preserves medical pack")
	PlayerData.player_hp -= 1
	pack._on_area_2d_body_entered(Utils.player)
	check(PlayerData.player_hp == PlayerData.player_hp_max,"medical pack heals only missing health")
	await clean()
	print("B16 PICKUP checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

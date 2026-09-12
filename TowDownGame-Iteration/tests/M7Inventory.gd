extends Node
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart()
	await get_tree().create_timer(0.3).timeout
	PlayerData.gold = 100000
	for id in Utils.weapon_list:
		Demo.try_purchase("weapon",id)
	for gun in PlayerData.player_weapon_list.values():
		print("INVENTORY ",JSON.stringify({"id":gun.weapon_id,"name":tr(gun.weapon_name),"stats":gun.effective,"base":gun.base_stats,"tags":gun.tags}))
	await Demo.quit_game()

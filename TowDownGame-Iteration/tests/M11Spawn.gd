extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(124)
	LevelServer.town.depart(29,true); LevelServer.timerStop(); await clean()
	var arena=LevelServer.town.arena
	Utils.player.global_position=arena.to_global(Vector2(375,0))
	await wait(0.05)
	check(arena.grid.is_point_solid(arena.cell(Utils.player.global_position)),"player beside wall lies in conservative AI margin")
	var point=arena.spawn_near(Utils.player.global_position,145,280,2)
	check(point!=Vector2.INF,"wall-edge player does not silence legal arrivals")
	if point!=Vector2.INF:
		check(point.distance_to(Utils.player.global_position)>=145 and not arena.grid.is_point_solid(arena.cell(point)),"wall-edge reinforcements remain safe and walkable")
		check(arena.grid.get_id_path(arena.cell(point),arena.nearest(Utils.player.global_position)).size()>1,"arrival has valid navigation to player vicinity")
	print("M11_SPAWN_CHECKS ",checks," FAILURES ",failures)
	LevelServer.return_to_camp(); await wait(0.2); dismiss(); await Demo.quit_game()

extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(0)
	Demo.open_panel(); await get_tree().create_timer(0.1,true).timeout
	Demo.root_lesson()
	check(LevelServer.state=="CAMP" and Demo.lesson_state=="explanation","explanation does not teleport")
	Demo.lesson_overlay.find_children("*","Button",true,false).filter(func(b): return b.text=="暂不训练")[0].pressed.emit()
	await get_tree().create_timer(0.1,true).timeout
	check(LevelServer.state=="CAMP" and Demo.lesson_state=="","cancel stays in camp")
	Demo.root_lesson(); Demo.start_root_lesson(); await wait(0.5)
	var boss=instance_from_id(LevelServer.boss_instance)
	var target=Utils.player.global_position
	var first_egg=get_tree().get_nodes_in_group("boss_ultimate")[0]
	Utils.player.global_position+=Vector2(0,90)
	var miss_deadline=Time.get_ticks_msec()+8000
	while is_instance_valid(first_egg) and Time.get_ticks_msec()<miss_deadline: await wait(0.02)
	check(not is_instance_valid(first_egg),"first missed projectile really left the arena")
	check(Demo.lesson_state=="objective","missed egg cannot complete tutorial")
	check(boss.attack_index==0 and boss.attack_kind=="ultimate","retry never falls through to normal boss patterns")
	Utils.player.global_position=target
	var deadline=Time.get_ticks_msec()+10000
	while Demo.lesson_state!="complete" and Time.get_ticks_msec()<deadline: await get_tree().create_timer(0.02,true).timeout
	check(Demo.lesson_state=="complete","retry real egg hit completes lesson")
	Demo.finish_root_lesson(); await wait(0.4)
	check(LevelServer.state=="CAMP" and get_tree().get_nodes_in_group("combat_transient").is_empty(),"return cleans lesson attacks")
	print("M12_LESSON_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()

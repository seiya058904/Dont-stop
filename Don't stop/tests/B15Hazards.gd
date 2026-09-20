extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); await clean()
	LevelServer.level=31; LevelServer.state="COMBAT"
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	var meteor = StageHazard.new()
	meteor.kind="meteor"; meteor.at=Utils.player.global_position; meteor.warning=1.5; meteor.active_time=0.35
	add_child(meteor); meteor.set_physics_process(false)
	var point=meteor.origin()
	var hp=PlayerData.player_hp
	meteor.phase_time=0.5; meteor._warning(0.1)
	check(PlayerData.player_hp==hp and meteor.phase=="warning","meteor warning never damages")
	meteor.visible_warning=2; meteor.phase_time=0; meteor._warning(0.01)
	check(PlayerData.player_hp<hp and meteor.phase=="active","meteor damages exactly at ground impact transition")
	var after=PlayerData.player_hp
	for i in 10: meteor._active(0.01)
	check(PlayerData.player_hp==after and not meteor.contains_player(),"meteor has no residual poison or repeated hit")
	check(meteor.origin()==point,"meteor ground point stays locked")
	meteor.queue_free()
	var shock=StageHazard.new(); shock.kind="shock"; shock.at=Utils.player.global_position+Vector2(0,100); shock.sweep=46
	add_child(shock); shock.set_physics_process(false)
	shock._advance(0.5); shock._clip()
	check(shock.origin().is_equal_approx(shock.global_position+Vector2(0,-23)),"moving shock has shared translated origin")
	shock.queue_free()
	for stage in range(31,41): check(not "poison" in ArenaHazards.plan(stage).kinds,"environment poison replaced stage %d"%stage)
	print("B15 HAZARDS checks=",checks," failures=",failures)
	await clean(); get_tree().quit(1 if failures else 0)

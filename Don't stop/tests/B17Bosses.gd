extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(0)
	var rows=[]
	for stage in [10,20,30,40]:
		stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.1)
		LevelServer.town.depart(stage,true)
		var boss = instance_from_id(LevelServer.boss_instance)
		check(is_instance_valid(boss),"real boss departure "+str(stage))
		if not is_instance_valid(boss): continue
		# Controlled scheduler observation; HP is restored and no victory is claimed.
		for tier in [1,2,3]:
			boss.phase_two = tier>=2; boss.phase_three = tier>=3
			boss.combo_queue.clear(); boss.attack_index=0
			var start=Time.get_ticks_msec()
			var before=boss.actions.duplicate()
			while Time.get_ticks_msec()-start<22000 and is_instance_valid(boss):
				PlayerData.player_hp=PlayerData.player_hp_max
				await wait(0.1)
			var requested=boss.actions.get("barrage_requested",0)-before.get("barrage_requested",0)
			var emitted=boss.actions.get("barrage_projectiles",0)-before.get("barrage_projectiles",0)
			rows.append({"stage":stage,"phase":tier,"seconds":22,"actions":boss.actions.duplicate(),"requested":requested,"emitted":emitted,"method":"controlled phase observation; HP replenished, not normal survival"})
			check(requested==emitted,"whole admitted waves fully emit %d phase %d"%[stage,tier])
			check(emitted>0,"reachable actual barrage %d phase %d"%[stage,tier])
	stop(); LevelServer.return_to_camp()
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b17-bosses.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"));file.close()
	print("B17 BOSSES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

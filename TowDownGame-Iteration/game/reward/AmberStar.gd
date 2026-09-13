extends BaseReward

var mark_dict = { #怪物标记
}

func afterAtk(monster:BaseMonster,hit_num):#怪物收到伤害后触发
	if mark_dict.has(monster.get_instance_id()):
		mark_dict[monster.get_instance_id()] += 1
	else:
		mark_dict[monster.get_instance_id()] = 1
		var target_id = monster.get_instance_id()
		var cleanup = clear_target.bind(target_id)
		if not monster.tree_exiting.is_connected(cleanup): monster.tree_exiting.connect(cleanup,CONNECT_ONE_SHOT)
	if mark_dict[monster.get_instance_id()] == 3:
		mark_dict[monster.get_instance_id()] = 0
		doBoom(monster)

func onKill(monster:BaseMonster): #击杀后触发
	if mark_dict.has(monster.get_instance_id()):
		mark_dict.erase(monster.get_instance_id())

func doBoom(monster:BaseMonster):
	var hurt = mini(count,6) * 5
	monster.onHit(hurt,false)
	Utils.showHitLabelMore(hurt,monster,Vector2(0,-5),Color.TOMATO)

func target_removed(target):
	clear_target(target.get_instance_id())

func clear_target(target_id):
	mark_dict.erase(target_id)

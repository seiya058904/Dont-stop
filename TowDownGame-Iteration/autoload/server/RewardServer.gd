extends Node
##======奖励全局管理=========
signal onRewardAdd(rw:BaseReward) #获得一个奖励
signal onRewardRemove(rw:BaseReward) #移除一个奖励

var reward_list = {
	"12" = preload("res://game/reward/Reward12.tscn"),
	"13" = preload("res://game/reward/Reward13.tscn"),
	"14" = preload("res://game/reward/Reward14.tscn"),
	"15" = preload("res://game/reward/Reward15.tscn"),
	"16" = preload("res://game/reward/Reward16.tscn"),
	"17" = preload("res://game/reward/Reward17.tscn"),
	"18" = preload("res://game/reward/Reward18.tscn"),
	"19" = preload("res://game/reward/Reward19.tscn"),
	"20" = preload("res://game/reward/Reward20.tscn"),
	"21" = preload("res://game/reward/Reward21.tscn"),
	"22" = preload("res://game/reward/Reward22.tscn"),
	"23" = preload("res://game/reward/Reward23.tscn"),
	"0" = preload("res://game/reward/GoldReward.tscn"),
	"1" = preload("res://game/reward/HpReward.tscn"),
	"2" = preload("res://game/reward/AlienHelmentReward.tscn"),
	"3" = preload("res://game/reward/WarningShield.tscn"),
	"4" = preload("res://game/reward/BlueAxe.tscn"),
	"5" = preload("res://game/reward/BlueBoots.tscn"),
	"6" = preload("res://game/reward/AmberStar.tscn"),
	"7" = preload("res://game/reward/HeathPack.tscn"),
	"8" = preload("res://game/reward/AmberSickle.tscn"),
	"9" = preload("res://game/reward/Battery.tscn"),
	"10" = preload("res://game/reward/BlueBacteria.tscn"),
	"11" = preload("res://game/reward/BlueCircuit.tscn")
}

var reward_shop_list = []
var reward_max = 3

func getShopList(is_reload = false):
	if reward_shop_list.is_empty() || is_reload:
		reward_shop_list.clear()
		var keys = reward_list.keys()
		keys.shuffle()
		for i in reward_max:
			reward_shop_list.append(keys.pop_back())
		# Keep three unique choices and at least two functional categories.
		if categories(reward_shop_list).size() == 1:
			for candidate in keys:
				if category(candidate) != category(reward_shop_list[0]):
					reward_shop_list[2] = candidate; break
	return reward_shop_list

func can_add(rw: BaseReward) -> bool:
	if not is_instance_valid(Utils.player): return false
	var node = Utils.player.reward_root.get_node_or_null(rw.reward_name)
	return node == null or node.count < node.max_count

func addReward(rw:BaseReward) -> bool:
	if not can_add(rw):
		rw.free()
		return false
	var node = Utils.player.reward_root.get_node_or_null(rw.reward_name)
	if node:
		node.count += 1
		rw.free()
		onRewardAdd.emit(node)
	else:
		rw.name = rw.reward_name
		Utils.player.reward_root.add_child(rw)
		onRewardAdd.emit(rw)
	return true

func removeReward(rw:BaseReward):
	if Utils.player:
		Utils.player.reward_root.remove_child(rw)
		emit_signal("onRewardRemove",rw)
		rw.queue_free()

func category(id) -> String:
	return "defense" if int(id) in [1,2,3,7,10,17,18,19] else ("utility" if int(id) in [0,5,13,20,21,22,23] else "attack")
func categories(ids: Array) -> Array:
	var result = []
	for id in ids:
		if not category(id) in result: result.append(category(id))
	return result
func rank(id: int) -> int:
	if not is_instance_valid(Utils.player): return 0
	for reward in Utils.player.reward_root.get_children():
		if reward.id == id: return reward.count
	return 0
func momentum() -> float:
	if not is_instance_valid(Utils.player): return 0.0
	for reward in Utils.player.reward_root.get_children():
		if reward.id == 22 and reward.moving_buff: return 0.03*reward.count
	return 0.0
func pickup_bonus() -> float:
	return DemoConfig.talent_value("T09",Demo.rank("T09"))+0.4*rank(23)

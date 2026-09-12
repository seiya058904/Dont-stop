extends Node
func _ready():
	TranslationServer.set_locale("zh_CN")
	var data = {"profile":DemoConfig.PROFILE,"weapons":[],"attachments":[],"talents":[],"legacy_rewards":[],"enemies":["E01","E02","E04","E05"],"bosses":[],"regions":["R1 improved original town block"],"encounters":DemoConfig.ENCOUNTERS}
	for id in Utils.weapon_list:
		var gun = Utils.weapon_list[id].instantiate()
		data.weapons.append({"id":id,"name":tr(gun.weapon_name),"scene":Utils.weapon_list[id].resource_path,"price":Utils.weapon_money_list[id],"base_damage":gun.damage,"rate":gun.fire_rate,"magazine":gun.bullets_max_count,"reload":gun.change_speed,"baseline":int(id)<10})
		gun.free()
	for id in Utils.am_dict:
		var am = Utils.am_dict[id].instantiate()
		data.attachments.append({"id":id,"name":tr(am.am_name),"scene":Utils.am_dict[id].resource_path,"price":am.money,"slot":am.am_type,"description":tr(am.am_info),"baseline":int(id)<10})
		am.free()
	for id in DemoConfig.TALENTS: data.talents.append({"id":id,"definition":DemoConfig.TALENTS[id]})
	for id in RewardServer.reward_list:
		var reward = RewardServer.reward_list[id].instantiate()
		data.legacy_rewards.append({"id":id,"name":tr(reward.reward_name),"persistent":not reward.only_start,"max":reward.max_count,"scene":RewardServer.reward_list[id].resource_path})
		reward.free()
	var file = FileAccess.open("res://docs/iteration/CONTENT-MANIFEST.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	print("MANIFEST weapons=",data.weapons.size()," attachments=",data.attachments.size()," specified_talents=",data.talents.size()," persistent_legacy=",data.legacy_rewards.filter(func(r): return r.persistent).size()," encounters=",data.encounters.size())
	get_tree().quit()

extends RefCounted
static func entries() -> Array:
	var rows=[]
	if not is_instance_valid(Utils.player): return rows
	var player=Utils.player
	if player.root_remaining>0: rows.append({"name":"束缚","value":"%.1fs" % player.root_remaining,"source":"母巢巨卵","info":"不能移动或冲刺，仍可瞄准、开火和装填。"})
	elif player.cc_immunity>0: rows.append({"name":"束缚免疫","value":"%.1fs" % player.cc_immunity,"source":"束缚保护","info":"免疫再次束缚。"})
	for pair in [["T19","护盾",Demo.cooldown("T19")],["T16","爆破",Demo.blast_cooldown],["T24","自动修复",Demo.heal_cooldown]]:
		if Demo.rank(pair[0])>0: rows.append({"name":pair[1],"value":"就绪" if pair[2]<=0 else "%.1fs" % pair[2],"source":DemoConfig.TALENTS[pair[0]].name,"info":DemoConfig.talent_info(pair[0])})
	if Demo.kill_stacks>0: rows.append({"name":"连杀加速","value":"%d层 · %.1fs" % [Demo.kill_stacks,maxf(0,Demo.stack_time)],"source":DemoConfig.TALENTS.T10.name,"info":DemoConfig.talent_info("T10")})
	if is_instance_valid(player.gun) and player.gun.first_round and Demo.rank("T12")>0:
		rows.append({"name":"首发","value":"就绪","source":DemoConfig.TALENTS.T12.name,"info":"实际补弹完成；下一次齐射获得首发增伤。"})
	if Demo.owned_global_upgrades.has("9"): rows.append({"name":"联动爆破","value":"就绪" if Demo.grenade_cooldown<=0 else "%.1fs" % Demo.grenade_cooldown,"source":"联动爆破核心","info":"真实命中自动爆破；公共1.75秒冷却。"})
	for reward in player.reward_root.get_children():
		if reward.id==22 and reward.get("moving_buff")==true: rows.append({"name":"动量环","value":"生效","source":"奖励 NPC","info":reward.reward_info})
		if reward.id==17 and reward.get("armed")==true: rows.append({"name":"反应装甲","value":"就绪","source":"奖励 NPC","info":reward.reward_info})
	return rows
static func display() -> String:
	var parts=[]
	for row in entries(): parts.append(row.name+"："+row.value)
	return "  ·  ".join(parts)

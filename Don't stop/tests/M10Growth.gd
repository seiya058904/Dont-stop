extends "res://tests/M8Runtime.gd"
var audit = []
func get_reward(id: int):
	for reward in Utils.player.reward_root.get_children():
		if reward.id == id: return reward
	return null
func give(id: int, count = 1):
	for i in count: check(RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate()),"add reward %d" % id)
	return get_reward(id)
func _ready():
	await boot(); await configure(0)
	check(RewardServer.reward_list.size()==24,"24 rewards")
	for i in 100:
		var choices = RewardServer.getShopList(true)
		check(choices.size()==3 and choices[0]!=choices[1] and choices[1]!=choices[2] and choices[0]!=choices[2] and RewardServer.categories(choices).size()>=2,"unique mixed choices")
	var seen = {}
	for id in RewardServer.reward_list:
		var reward = RewardServer.reward_list[id].instantiate()
		check(reward.reward_image != null,"reward icon "+id)
		audit.append({"id":id,"max_count":reward.max_count,"info":reward.reward_info,"persistent":not reward.only_start})
		reward.free()
	var cost = 0
	for id in Utils.am_dict:
		var upgrade = Utils.am_dict[id].instantiate()
		check(upgrade.money>=300,"upgrade price "+id); cost += upgrade.money; upgrade.free()
	check(cost>=15000 and cost<=22000,"upgrade total "+str(cost))
	Demo.open_panel(); Demo.ui.switch_tab("weapon")
	for id in Utils.weapon_list:
		Demo.ui.detail_actions[id].call()
		var preview = Demo.ui.weapon_preview
		var gun = Utils.weapon_list[id].instantiate()
		check((preview.texture==gun.image or preview.texture.atlas==gun.image) and preview.custom_minimum_size==Vector2(70,24) and not Demo.ui.detail.is_ancestor_of(preview),"fixed actual preview outside scrolling detail "+id)
		gun.free()
		seen[id] = true
	dismiss(); await wait(0.1)
	var gun = Utils.player.gun
	var base = gun.effective.duplicate()
	Demo.owned_global_upgrades = ["110","1","0","117","111"]
	Demo.refresh(); var a = gun.effective.duplicate()
	Demo.owned_global_upgrades = []
	Demo.talents = {"T01":1,"T02":1,"T03":1,"T04":1,"T05":1,"T06":1,"T07":1,"T08":1,"T18":1}
	Demo.refresh(); var b = gun.effective.duplicate()
	Demo.owned_global_upgrades = ["110","1","0","117","111"]
	Demo.refresh(); var ab = gun.effective.duplicate()
	check(is_equal_approx(ab.crit,base.crit+0.08+0.05),"crit additive pp")
	for key in ["damage","magazine","range","impulse"]: check(ab[key]>maxf(a[key],b[key]),"A+B "+key)
	check(ab.reload<minf(a.reload,b.reload),"A+B reload")
	var speed = Utils.player.SPEED
	give(5); give(20); var momentum = give(22)
	momentum.moving_buff = true; momentum.set_physics_process(false); Demo.refresh()
	check(Utils.player.SPEED>speed+5 and gun.effective.rate>b.rate,"talent plus boots plus momentum")
	check(gun.effective.impulse>ab.impulse,"three-layer impulse")
	var old_hp = PlayerData.player_hp_max
	give(2); Demo.refresh(); check(PlayerData.player_hp_max==old_hp+3,"talent and helmet coexist")
	var pulse = give(15)
	var target = enemy(Vector2(150,0),10000)
	target.training = true
	var hp = target.HP
	var context = gun.damage_context(); context.crit = 0
	for i in 7: Combat.hit(target,context)
	check(target.HP < hp-context.damage*7,"pulse seventh direct hit actual damage")
	check(pulse.direct_hits==0,"pulse resets")
	context.depth = 1; Combat.hit(target,context); check(pulse.direct_hits==0,"derived no proc")
	context.depth = 0
	var ember = give(12,4); var frost = give(13,4)
	context.burn_talent = 0.2; context.slow = 0.08
	for i in 100: Combat.hit(target,context)
	check(target.burns.has("R12") and target.burns.has("T15"),"two burn sources survive")
	check(target.slows.has("R13") and target.slows.has("T17") and is_equal_approx(target.slow_amount,0.28),"two slows add")
	var magnet = give(23); check(is_equal_approx(RewardServer.pickup_bonus(),0.4),"magnet reward")
	Demo.talents.T09 = 1; check(is_equal_approx(RewardServer.pickup_bonus(),0.6),"magnet talent plus reward")
	LevelServer.state = "COMBAT"
	PlayerData.player_hp_max = 20; PlayerData.player_hp = 20
	var armor = give(17)
	Utils.player.onHit(2); var before = PlayerData.player_hp; Utils.player.onHit(2)
	check(is_equal_approx(before-PlayerData.player_hp,1.6),"reactive next ordinary hit")
	var cell = give(19); PlayerData.player_hp = 6; Utils.player.onHit(1)
	check(PlayerData.player_hp==6 and cell.cooldown==20,"emergency cell actual hit")
	PlayerData.player_hp = 20; before = PlayerData.player_hp
	Utils.player.on_percentage_hit(0.3)
	check(is_equal_approx(before-PlayerData.player_hp,6),"percentage current max independent from flat pressure")
	check(Utils.player.apply_root(),"root starts")
	check(not Utils.player.apply_root(),"root cannot refresh")
	await wait(0.5); check(Utils.player.root_remaining==0 and Utils.player.cc_immunity>1,"post root immunity")
	check(not Utils.player.apply_root(),"immunity blocks chain")
	await wait(1.3); check(Utils.player.apply_root(),"root expires normally")
	LevelServer.state = "CAMP"; await wait(0.1)
	for id in range(12,24):
		if not get_reward(id): give(id)
	var sickle = give(8); sickle.doBuff()
	var battery = give(9); battery.is_time_out = true
	Demo.refresh()
	Demo.purchases.clear()
	for reward in Utils.player.reward_root.get_children():
		for i in reward.count: Demo.purchases.append(str(reward.id))
	Demo.save_path = "res://docs/iteration/evidence/m10/growth-save.json"
	Demo.test_mode = false; check(Demo.save_camp().success,"save full growth")
	Demo.owned_global_upgrades.sort()
	var saved = JSON.parse_string(JSON.stringify(Demo.snapshot())); var stats = gun.effective.duplicate(); speed = Utils.player.SPEED
	for i in 3:
		check(Demo.load_camp(),"load growth "+str(i))
		for key in saved:
			if Demo.snapshot()[key]!=saved[key]: print("SAVE DIFF ",key," before ",JSON.stringify(saved[key])," after ",JSON.stringify(Demo.snapshot()[key]))
		check(JSON.parse_string(JSON.stringify(Demo.snapshot()))==saved,"idempotent graph "+str(i))
		check(Utils.player.gun.effective==stats and Utils.player.SPEED==speed,"idempotent attributes "+str(i))
		check(Demo.save_camp().success,"repeat save")
	var file = FileAccess.open("res://docs/iteration/evidence/m10/growth.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rewards":audit,"upgrade_total":cost,"previews":seen.size()},"\t")); file.close()
	print("M10_GROWTH_CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)

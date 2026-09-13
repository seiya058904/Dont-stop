extends "res://tests/M8Runtime.gd"
var panel
func snap(name: String):
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(0.05,true).timeout
	RenderingServer.force_draw(false)
	var picture=play_view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	picture.save_png("res://docs/iteration/evidence/m11/"+name+".png")
func expected(ledger,stat: String) -> float:
	var flat=0.0; var percentage=0.0; var product=1.0
	for row in ledger.ordered(stat):
		if not row.active: continue
		match row.operation:
			"flat","percentage_point": flat+=float(row.value)
			"additive_percentage": percentage+=float(row.value)
			"multiplier": product*=float(row.value)
	var value=flat*(1+percentage)*product
	if stat=="crit": value=clampf(flat,0,1)
	if stat=="reload": value=maxf(DemoConfig.MIN_RELOAD_SECONDS,value)
	if stat=="magazine": value=maxi(1,int(value))
	return value
func _ready():
	await boot()
	var installed=load("res://tests/M11Builds.gd").install("B")
	check(installed.failures.is_empty(),"legal mature profile")
	PlayerData.player_level=3; PlayerData.player_hp_max=10; PlayerData.player_hp=2
	PlayerData.player_exp=PlayerData.getMaxExp()-1
	var points=PlayerData.reward_point
	PlayerData.player_exp+=1
	check(PlayerData.player_level==4 and is_zero_approx(PlayerData.player_exp),"exact EXP threshold")
	check(is_equal_approx(PlayerData.player_hp,2.5) and is_equal_approx(PlayerData.player_hp_max,10.5),"level grants only new half HP, never full heal")
	check(is_equal_approx(PlayerData.player_damage,1.2) and PlayerData.reward_point==points+1,"exact level damage and reward point")
	var ui=Utils.canvasLayer.get_node("GameUI")
	check(ui.level_label.text=="Lv. 4" and "EXP" in ui.exp_text.text,"level and numeric EXP visible")
	check("+0.5" in ui.level_notice.text and "+0.3" in ui.level_notice.text and "+1" in ui.level_notice.text,"notice uses actual progression rewards")
	await snap("level-reward")
	var threshold=PlayerData.PROGRESSION.threshold(4)+PlayerData.PROGRESSION.threshold(5)
	PlayerData.player_exp=threshold+3
	check(PlayerData.player_level==6 and is_equal_approx(PlayerData.player_exp,3),"multiple levels retain excess EXP")
	PlayerData.gold=100000
	var gun=Utils.player.gun
	gun.spin=1; gun.drive_spin(true,1)
	Demo.open_stats(); await get_tree().create_timer(0.1,true).timeout
	panel=Demo.pause_stack.back()
	check(panel.get_script()==load("res://ui/StatPanel.gd"),"camp opens actual stat panel")
	for stat in ["damage","crit","magazine","reload","range","impulse"]:
		panel.source_buttons[stat].pressed.emit()
		check(is_equal_approx(panel.values[stat],panel.snapshot.weapon[stat]),"UI final value "+stat)
		if stat!="damage": check(is_equal_approx(expected(panel.snapshot.ledger,stat),panel.values[stat]),"source reconstruction "+stat)
	check(is_equal_approx(expected(panel.snapshot.ledger,"damage"),panel.values.damage),"damage buckets reconstruct final shot")
	check(panel.snapshot.ledger.ordered("crit").any(func(r): return r.source_type=="upgrade" and r.operation=="percentage_point"),"crit uses additive percentage points")
	check(panel.snapshot.ledger.ordered("reload").any(func(r): return r.operation=="multiplier"),"reload multiplier remains separate")
	var source_order={"base":0,"level":1,"legacy":2,"upgrade":3,"talent":4,"reward":5,"condition":6,"rule":7,"history":8}
	var last_type=-1
	for row in panel.snapshot.ledger.ordered("damage"):
		check(source_order[row.source_type]>=last_type,"stable source ordering "+row.source_name); last_type=source_order[row.source_type]
	Demo.crowd_active=true; gun.first_round=true; Demo.talents.T12=2
	var conditional=EffectiveStats.inspect(gun)
	check(is_equal_approx(conditional.weapon.damage,gun.shot_context().damage),"active conditional sources equal actual first shot")
	check(conditional.ledger.ordered("damage").any(func(r): return r.source_id=="T12" and r.active),"first shot shown as conditional active")
	var volley=EffectiveStats.inspect(gun)
	check(is_equal_approx(expected(volley.ledger,"damage"),volley.weapon.damage),"consumed first shot remains attributed within same volley frame")
	Demo.crowd_active=false
	panel.selected="damage"; panel.render(); await get_tree().create_timer(0.1,true).timeout; await snap("stats-weapon")
	panel.tab="player"; panel.render()
	for stat in ["speed","max_hp"]: check(is_equal_approx(expected(panel.snapshot.ledger,stat),panel.values[stat]),"player sources reconstruct "+stat)
	check(panel.values.speed==Utils.player.SPEED and panel.values.max_hp==PlayerData.player_hp_max,"player UI equals live values")
	await snap("stats-player")
	panel.tab="effects"; panel.render(); await snap("stats-effects")
	panel.tab="level"; panel.render(); await snap("stats-level-help")
	panel.queue_free(); await wait(0.1)
	Demo.open_settings(); await get_tree().create_timer(0.1,true).timeout
	var settings=Demo.pause_stack.back()
	var buttons=settings.find_children("*","Button",true,false).filter(func(b): return b.text=="角色属性")
	check(buttons.size()==1,"pause exposes stat panel entry")
	buttons[0].pressed.emit(); await get_tree().create_timer(0.1,true).timeout
	check(Demo.pause_stack.size()==2,"stat overlay retains paused parent")
	dismiss(); await wait(0.1)
	for id in Utils.weapon_list:
		if not PlayerData.player_weapon_list.has(int(id)): Demo.try_purchase("weapon",str(id))
		gun=PlayerData.player_weapon_list[int(id)]; Utils.player.changeWeapon(int(id)); gun.set_process(false); gun.set_physics_process(false)
		var inspected=EffectiveStats.inspect(gun)
		check(is_equal_approx(inspected.weapon.damage,gun.shot_context().damage),"actual outgoing context equals displayed shot "+str(id))
		check(inspected.weapon.crit==gun.effective.crit and inspected.weapon.magazine==gun.bullets_max_count and inspected.weapon.reload==gun.effective.reload,"live gun fields match panel "+str(id))
		check(inspected.weapon.projectile_count==gun.projectile_count(),"runtime emission count API "+str(id))
	var old=JSON.parse_string(JSON.stringify(Demo.snapshot()))
	Demo.test_mode=false; Demo.save_path="res://docs/iteration/evidence/m11/legacy-save.json"; Demo.save_camp(); Demo.test_mode=true
	for i in 3:
		check(Demo.load_camp(),"M10 schema6 save load "+str(i))
		var after=JSON.parse_string(JSON.stringify(Demo.snapshot()))
		for key in ["level","exp","hp_max","talents","owned_global_upgrades","legacy"]: check(old[key]==after[key],"preserve saved "+key)
	Demo.cooldown("T19"); Demo.talent_cooldowns.T19=2.3
	var hud=Utils.canvasLayer.get_children().filter(func(n): return n.get_script()==load("res://ui/DemoHUD.gd"))[0]
	hud.update_text(); check("护盾：2.3s" in hud.text and not "修复2" in hud.text and not "火力" in hud.text,"HUD names and cooldown semantics")
	Demo.talent_cooldowns.T19=0; hud.update_text(); check("护盾：就绪" in hud.text,"ready state distinct from zero seconds")
	Demo.open_panel(); await get_tree().create_timer(0.1,true).timeout
	var lesson_buttons=Demo.ui.find_children("*","Button",true,false).filter(func(b): return b.text=="束缚攻击训练")
	check(lesson_buttons.size()==1,"visible deterministic root lesson entry")
	lesson_buttons[0].pressed.emit()
	check(Demo.lesson_state=="explanation" and LevelServer.state=="CAMP","explanation before teleport")
	Demo.lesson_overlay.find_children("*","Button",true,false).filter(func(b): return b.text=="开始训练")[0].pressed.emit()
	var start=Time.get_ticks_msec()
	while Utils.player.root_remaining<=0 and Time.get_ticks_msec()-start<7000: await wait(0.02)
	check(Utils.player.root_remaining>0,"deterministic real B02 egg collision roots player")
	hud.update_text(); check(hud.root_icon.visible and "束缚：" in hud.text,"root icon and countdown")
	var position=Utils.player.global_position
	Input.action_press("right"); await wait(0.1); Input.action_release("right")
	check(Utils.player.global_position.distance_to(position)<1,"root disables actual movement")
	await snap("root-active")
	await wait(0.5); hud.update_text(); check(Utils.player.cc_immunity>0 and "束缚免疫" in hud.text,"anti-chain immunity shown")
	await snap("root-immunity")
	check(not Utils.player.apply_root(),"cannot chain root during immunity")
	var lesson_end=Time.get_ticks_msec()
	while Demo.lesson_state!="complete" and Time.get_ticks_msec()-lesson_end<7000: await wait(0.1)
	check(Demo.lesson_state=="complete","completion requires root hit and recovery")
	Demo.lesson_overlay.find_children("*","Button",true,false).filter(func(b): return b.text=="返回营地")[0].pressed.emit()
	await wait(0.3)
	check(LevelServer.state=="CAMP" and get_tree().get_nodes_in_group("combat_transient").is_empty(),"root lesson return button returns to camp and cleans attacks")
	LevelServer.return_to_camp(); await wait(0.3); dismiss()
	print("M11_CLARITY_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()

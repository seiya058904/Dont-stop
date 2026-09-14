extends "res://tests/M8Runtime.gd"
var panel
func snap(name: String):
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(0.1,true).timeout
	RenderingServer.force_draw(false)
	var picture=play_view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	picture.save_png("res://docs/iteration/evidence/m12/"+name+".png")
func _ready():
	await boot(); configure(0,true)
	check(Utils.weapon_list.size()==24 and Utils.am_dict.size()==24 and DemoConfig.TALENTS.size()==24 and RewardServer.reward_list.size()==24,"frozen weapons upgrades talents rewards counts")
	check(M5Content.ENEMIES.size()==12 and M5Content.BOSSES.size()==3 and M5Content.REGIONS.size()==6 and DemoConfig.ENCOUNTERS.size()==30,"frozen enemy boss region encounter counts")
	for id in RewardServer.reward_list:
		if int(id) in [0,1]: continue
		RewardServer.addReward(RewardServer.reward_list[id].instantiate())
	Demo.refresh(); Demo.open_stats(); await get_tree().create_timer(0.1,true).timeout
	panel=Demo.pause_stack.back()
	check(panel.tab=="build","build overview is the default")
	check(panel.owned_icons.size()==Demo.owned_global_upgrades.size()+Demo.talents.size()+Utils.player.reward_root.get_child_count(),"all owned items represented")
	for stat in ["damage","crit","rate","magazine","reload","range","max_hp","speed"]:
		check(is_equal_approx(panel.values[stat],panel.snapshot.player.get(stat,panel.snapshot.weapon.get(stat,0))),"final runtime equals UI "+stat)
		check(panel.source_buttons[stat].get_global_rect().end.y<230,"final visible without scrolling "+stat)
	var reconstruct=load("res://tests/M11Clarity.gd").new()
	for stat in ["damage","crit","rate","magazine","reload","max_hp","speed"]:
		check(is_equal_approx(reconstruct.expected(panel.snapshot.ledger,stat),panel.values[stat]),"actual source operations reconstruct final "+stat)
	reconstruct.free()
	for key in panel.owned_icons:
		var icon=panel.owned_icons[key]
		# Product decision for this round: inside the stat sheet the weapon-upgrade
		# and talent entries are text only. They must have NO icon and still carry
		# the full source tooltip; every other entry kind keeps its icon. Asserting
		# both directions keeps this a contract check rather than a relaxed one.
		var text_only_entry = key.begins_with("upgrade/") or key.begins_with("talent/")
		if text_only_entry:
			check(icon.text_only and icon.picture==null and icon.icon==null,"text-only entry has no icon "+key)
			check(icon.get_theme_constant("icon_max_width")==0 or not icon.expand_icon,"text-only entry reserves no icon space "+key)
		else:
			check(not icon.text_only and icon.picture!=null,"icon entry keeps its icon "+key)
		check(not icon.description.is_empty() and "来源：" in icon.description,"source tooltip "+key)
		var tooltip=icon._make_custom_tooltip(icon.description)
		if text_only_entry:
			check(tooltip.get_child(0).texture==null,"text-only tooltip draws no icon "+key)
		else:
			check(tooltip.get_child(0).texture==icon.display_picture and (icon.display_picture==icon.picture or icon.display_picture.atlas==icon.picture),"tooltip reuses official icon "+key)
		tooltip.free()
		var scroll=icon.get_parent().get_parent().get_parent()
		scroll.ensure_control_visible(icon)
		await get_tree().create_timer(0.03,true).timeout
		var motion=InputEventMouseMotion.new(); motion.position=icon.get_global_rect().get_center(); play_view.push_input(motion,true)
		await get_tree().create_timer(0.03,true).timeout
		check(is_instance_valid(icon.popup) and icon.popup.visible,"viewport mouse hover opens "+key)
		if is_instance_valid(icon.popup):
			check(icon.popup.get_meta("source")==icon.description,"hover source correct "+key)
			check(Rect2(Vector2.ZERO,Vector2(410,230)).encloses(icon.popup.get_global_rect()),"hover stays inside viewport "+key)
			if key in ["upgrade/124","talent/T24","reward/11"]: await snap(key.replace("/","-")+"-hover")
		motion=InputEventMouseMotion.new(); motion.position=Vector2(1,1); play_view.push_input(motion,true)
		check(not is_instance_valid(icon.popup) or not icon.popup.visible,"mouse exit closes "+key)
	for reward in Utils.player.reward_root.get_children():
		var icon=panel.owned_icons["reward/"+str(reward.id)]
		check(icon.picture==reward.reward_image and icon.get_parent() is GridContainer and icon.get_parent().columns==4,"reward official icon grid "+str(reward.id))
	for scroll in panel.overview.find_children("*","ScrollContainer",true,false): scroll.scroll_vertical=0
	await snap("build-overview")
	for kind in ["upgrade","talent","reward"]:
		panel.show_category(kind); await snap(kind+"-total")
	panel.tab="weapon"; panel.render(); panel.show_sources("damage")
	check(panel.details.find_children("*","Button",true,false).size()>0,"category drilldown available")
	await snap("damage-categories")
	panel.queue_free(); await wait(0.1); Demo.open_panel(); await get_tree().create_timer(0.1,true).timeout
	var shop=Demo.ui; shop.tier_filter=5; shop.tier_box.select(5); shop.selection="124"; shop.render(); shop.detail_actions["124"].call(); await snap("shop-tier5")
	check(shop.action_bar.get_global_rect().end.y<230,"shop CTA remains visible")
	check("+13.0pp" in shop.comparison("crit",0.05,0.18),"comparison percentage points")
	check("-25%" in shop.comparison("rate",10,7.5),"comparison percentage modifiers")
	dismiss(); await wait(0.1)
	print("M12_UX_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()

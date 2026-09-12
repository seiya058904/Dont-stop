extends "res://tests/M4UI.gd"
func _ready():
	Demo.test_mode = true; Demo.save_path = "res://evidence/m6-save-ui.json"
	var viewport = SubViewport.new(); viewport.size = Vector2i(1536,864); viewport.world_2d = get_viewport().world_2d
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED; add_child(viewport)
	var main = load("res://game/map/Main.tscn").instantiate(); viewport.add_child(main); Utils.gameStart(); await wait(0.3)
	var fresh = Demo.snapshot().duplicate(true)
	check(Demo.valid_save(fresh) and fresh.schema_version == 4,"current new save valid")
	Demo.open_panel(); await frames(); var panel = Demo.ui
	for id in Utils.weapon_list:
		panel.switch_tab("weapon"); panel.selection = id; panel.render()
		var before = PlayerData.gold
		check(("价格：%d金币" % Utils.weapon_money_list[id]) in detail_text(panel),"weapon displayed price "+id)
		check(Demo.try_purchase("weapon",id).success and PlayerData.gold == before-Utils.weapon_money_list[id],"weapon actual payment "+id)
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	for id in DemoConfig.TALENTS: Demo.try_purchase("talent",id,"gold")
	panel.switch_tab("weapon"); panel.search_text = ""; panel.render()
	check(panel.detail_actions.size() == 24,"24 unique weapon UI IDs")
	for id in Utils.weapon_list:
		panel.search_text = WeaponCatalog.definition(int(id)).get("plan",id); panel.render()
		check(panel.detail_actions.has(id),"every gun searchable "+id)
	panel.search_text = "no-such-content-606"; panel.render()
	check(panel.detail_actions.is_empty() and "没有匹配条目" in detail_text(panel),"search empty state actionable")
	panel.search_text = ""; panel.search_box.text = ""
	panel.switch_tab("attachment"); panel.compatible_only = true
	for id in Utils.weapon_list:
		panel.selected_gun = int(id); panel.render()
		var expected = []
		for am in PlayerData.player_am_list.values():
			if am.can_equip(PlayerData.player_weapon_list[int(id)]): expected.append(str(am.am_id))
		expected.sort(); var actual = panel.detail_actions.keys(); actual.sort()
		check(actual == expected,"24 attachment filter matches actual equip contract for gun "+id)
	panel.switch_tab("talent"); panel.render()
	check(panel.detail_actions.size() == 24,"24 unique talent UI IDs")
	panel.switch_tab("stage"); panel.render()
	check(panel.detail_actions.size() == 30,"30 unique encounter UI IDs")
	for stage in DemoConfig.ENCOUNTERS:
		panel.detail_actions[str(stage)].call()
		check(DemoConfig.ENCOUNTERS[stage].name in detail_text(panel),"stage detail actual name "+str(stage))
	panel.queue_free(); await frames()
	var gun = PlayerData.player_weapon_list[0]
	for am in PlayerData.player_am_list.values():
		if am.can_equip(gun): gun.addAttachMent(am)
	Utils.player.changeWeapon(0); gun.bullets_count = 3; PlayerData.player_ammo = 77
	Demo.next_stage = 21; Demo.selected_stage = 30
	var current = Demo.snapshot().duplicate(true)
	for version in [1,2,3,4]:
		var data = current.duplicate(true); data.schema_version = version
		if version < 4: data.erase("campaign_complete")
		if version < 3: data.erase("talent_payments")
		if version < 2: data.erase("legacy"); data.erase("legacy_state")
		check(Demo.valid_save(data),"valid legacy schema "+str(version))
		check(Demo.save_store.save(Demo.save_path,data).success and Demo.load_camp(),"actual migration schema "+str(version))
		var gold = PlayerData.gold; var points = PlayerData.reward_point
		for cycle in 3:
			check(Demo.save_store.save(Demo.save_path,Demo.snapshot()).success and Demo.load_camp(),"repeat save restore migrated graph")
			check(PlayerData.gold == gold and PlayerData.reward_point == points and PlayerData.player_weapon_list.size() == 24 and PlayerData.player_am_list.size() == 24,"migration no resource or equipment duplication")
			check(Utils.player.gun.weapon_id == 0 and Utils.player.gun.bullets_count == 3 and PlayerData.player_ammo == 77 and Demo.next_stage == 21 and Demo.selected_stage == 30,"migration ammo equipped stage preserved")
		var refund = Demo.reset_preview()
		check(refund.gold == (2400 if version >= 3 else 0),"historical payment never invented")
	for mode in ["weapon","attachment","talent","equipped","removed_reference","duplicate_instance","duplicate_weapon","stage","missing_gold","missing_payments","missing_campaign","overfull_ammo","duplicate_payment"]:
		var bad = current.duplicate(true)
		match mode:
			"weapon": bad.weapons[0].id = "removed-weapon"
			"attachment": bad.attachments[0].definition = "removed-attachment"
			"talent": bad.talents["T99"] = 1
			"equipped": bad.equipped = "999"
			"removed_reference": bad.attachments[0].gun = "999"
			"duplicate_instance": bad.attachments.append(bad.attachments[0].duplicate())
			"duplicate_weapon": bad.weapons.append(bad.weapons[0].duplicate())
			"stage": bad.selected_stage = 31
			"missing_gold": bad.erase("gold")
			"missing_payments": bad.erase("talent_payments")
			"missing_campaign": bad.erase("campaign_complete")
			"overfull_ammo": bad.weapons[0].ammo = 999999
			"duplicate_payment": bad.talent_payments.append(bad.talent_payments[0].duplicate())
		check(not Demo.valid_save(bad),"invalid graph rejected "+mode)
	Demo.save_store.save(Demo.save_path,current); check(Demo.load_camp(),"restore current schema")
	var refund = Demo.reset_preview(); var gold = PlayerData.gold
	check(Demo.reset_talents(refund.revision).success and PlayerData.gold == gold+refund.gold,"refund actual ledger")
	check(not Demo.reset_talents(refund.revision).success and PlayerData.gold == gold+refund.gold,"duplicate refund rejected")
	Demo.save_store.save(Demo.save_path,Demo.snapshot()); check(Demo.load_camp() and Demo.reset_preview().gold == 0,"refund record survives reload without replay")
	Demo.open_panel(); await frames(); panel = Demo.ui; panel.selection = "0"; panel.render()
	check("已装备" in detail_text(panel) and panel.detail_actions.size() == 24,"restored UI matches equipped graph")
	panel.queue_free(); await frames()
	print("M6 SAVE UI SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

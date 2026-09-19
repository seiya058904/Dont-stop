extends "res://tests/M8Runtime.gd"
## B13 shop UI contract. The camp panel must speak the three-quality system on BOTH growth
## tabs: quality names on cards and in details, the quality filter selects exactly its
## members, talent details show per-rank prices for BOTH currencies, an unowned upgrade
## previews its real 当前 → 购买后 delta, the equipped weapon offers 卸下武器, and the
## unarmed state reads as such everywhere.

func has_quality_prefix(text: String) -> bool:
	for qname in ["普通 ","稀有 ","传说 "]:
		if text.begins_with(qname): return true
	return false

func card_texts(panel) -> Array:
	var texts: Array = []
	for child in panel.listing.get_children():
		if child is Button: texts.append(child.text)
	return texts

func detail_text_of(panel) -> String:
	var text := ""
	for child in panel.detail.get_children():
		if child is Label: text += child.text+"\n"
	return text

func find_button(panel, text_value: String) -> Button:
	# CampPanel routes detail-page buttons into action_bar, not detail.
	for box in [panel.detail, panel.action_bar]:
		for child in box.get_children():
			if child is Button and child.text == text_value: return child
	return null

func stat_panel():
	var script = load("res://ui/StatPanel.gd")
	for child in Utils.canvasLayer.get_children():
		if child.get_script() == script: return child
	return null

func _ready():
	await boot()
	configure(0,false)
	Demo.open_panel(); await wait(0.1)
	var panel = Demo.ui
	# --- upgrade tab: quality filter, quality-prefixed cards ------------------------------
	panel.switch_tab("attachment"); await wait(0.1)
	var filter_texts: Array = []
	for i in panel.quality_box.item_count: filter_texts.append(panel.quality_box.get_item_text(i))
	check(str(filter_texts)==str(["全部品质","普通","稀有","传说"]),"upgrade filter carries exactly the three qualities")
	var all_cards := card_texts(panel)
	check(all_cards.size()==24,"all 24 upgrade cards render")
	for text in all_cards:
		check(has_quality_prefix(text),"upgrade card carries a quality prefix: "+text)
		check("金币" in text,"upgrade card carries the price or owned marker: "+text)
	for q in [1,2,3]:
		panel.upgrade_quality_filter = q; panel.render()
		var texts := card_texts(panel)
		var expected := 0
		for v in AttachmentCatalog.QUALITY.values():
			if v == q: expected += 1
		check(texts.size()==expected,"quality filter %d shows exactly its members"%q)
		for text in texts: check(text.begins_with(AttachmentCatalog.QUALITY_NAMES[q-1]+" "),"filtered card keeps the quality prefix")
	panel.upgrade_quality_filter = 0; panel.render()
	# --- upgrade detail: name, quality, price, effect, global line, live preview ------------
	panel.selection = "118"; panel.render()
	var detail := detail_text_of(panel)
	check("贯穿弹药包" in detail and "稀有" in detail,"upgrade detail names the entry and its quality")
	check("1080金币" in detail,"upgrade detail shows the catalog price")
	check(AttachmentCatalog.DEFINITIONS[118].info in detail,"upgrade detail shows the real effect")
	check("所有当前和未来武器自动生效" in detail,"upgrade detail states the global rule")
	check("当前 → 购买后" in detail,"an unowned upgrade previews the real delta on the current gun")
	check(find_button(panel,"%d金币 | 购买" % AttachmentCatalog.PRICES[118]) != null,"purchase button carries the price")
	panel.purchase("attachment","118")
	await wait(0.1)
	panel.selection = "118"; panel.render()
	detail = detail_text_of(panel)
	check("√ 已激活" in detail,"owned upgrade shows the activated state")
	check(not "当前 → 购买后" in detail,"no purchase preview for an owned upgrade")
	# --- talent tab: quality + rank cards, per-rank both-currency prices ---------------------
	panel.switch_tab("talent"); await wait(0.1)
	var talent_cards := card_texts(panel).filter(func(t): return has_quality_prefix(t))
	check(talent_cards.size()==24,"all 24 talent cards carry quality and rank")
	for text in talent_cards: check("/" in text,"talent card shows rank x/y: "+text)
	panel.upgrade_quality_filter = 3; panel.render()
	var legendary := card_texts(panel).filter(func(t): return has_quality_prefix(t))
	check(legendary.size()==5,"the legendary filter shows exactly the legendary talents")
	for text in legendary: check(text.begins_with("传说 "),"legendary cards are prefixed 传说")
	panel.upgrade_quality_filter = 0; panel.render()
	panel.selection = "T02"; panel.render()
	detail = detail_text_of(panel)
	check("稀有" in detail,"talent detail names its quality")
	check("品质：稀有（价值等级；与当前等级独立）" in detail,"talent detail separates quality from rank")
	check("0 / 3" in detail,"talent detail shows the current rank")
	check("400金币 或 2天赋点" in detail,"talent detail shows the next-rank gold and point prices")
	check(DemoConfig.talent_effect("T02",1) in detail,"talent detail states the next-rank effect")
	check(find_button(panel,"金币购买") != null and find_button(panel,"天赋点升级") != null,"both purchase routes are offered")
	# --- weapon tab: the equipped weapon offers the unequip action ---------------------------
	panel.switch_tab("weapon"); panel.selection = "0"; panel.render()
	check(find_button(panel,"卸下武器") != null,"the equipped weapon offers 卸下武器")
	panel.purchase("weapon","4")
	configure(4,false)
	panel.selection = "4"; panel.render()
	check(find_button(panel,"卸下武器") != null,"the freshly equipped weapon offers 卸下武器")
	var unequip_button := find_button(panel,"卸下武器")
	unequip_button.pressed.emit()
	await wait(0.1)
	check(Utils.player.gun == null,"clicking 卸下武器 leaves the player unarmed")
	check(Demo.explicitly_unequipped,"the panel unequip records the intent")
	panel.render()
	check(find_button(panel,"已拥有 | 装备") != null,"unarmed weapon page offers re-equip")
	# --- the stat panel speaks the unarmed state ---------------------------------------------
	Demo.open_stats(); await wait(0.1)
	var stats = stat_panel()
	check(stats != null,"stat panel opens")
	var stat_text := ""
	for child in stats.listing.get_children():
		if child is Label: stat_text += child.text+"\n"
	check("未装备武器" in stat_text,"stat panel names the unarmed state")
	for menu in Demo.pause_stack.duplicate():
		if menu != panel: Demo.pop_pause(menu); menu.queue_free()
	print("B13_UI_CHECKS ",checks," FAILURES ",failures)
	dismiss(); await wait(0.1)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

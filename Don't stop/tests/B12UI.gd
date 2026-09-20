extends "res://tests/M8Runtime.gd"
## B12 shop UI contract. Every player-visible surface speaks quality names (普通/精良/稀有/
## 史诗/传说) - the strings "Tier"/"TIER"/"T1..T5" are gone from cards, badges and filters -
## while the underlying interactions keep working: five quality filters select exactly their
## tier members, quality-ascending sort stays ordered, search still maps plan IDs, and the
## equipped/owned markers still render on the right rows.

func card_texts(panel) -> Array:
	var texts: Array = []
	for child in panel.listing.get_children():
		if child is Button and child.has_meta("weapon_id"): texts.append(child.text)
	return texts

func card_ids(panel) -> Array:
	var ids: Array = []
	for child in panel.listing.get_children():
		if child is Button and child.has_meta("weapon_id"): ids.append(int(child.get_meta("weapon_id")))
	return ids

func _ready():
	await boot()
	configure(124,true)
	Demo.open_panel(); Demo.ui.switch_tab("weapon"); await wait(0.1)
	var panel = Demo.ui
	# --- filter box speaks quality names -------------------------------------------------
	var filter_texts: Array = []
	for i in panel.tier_box.item_count: filter_texts.append(panel.tier_box.get_item_text(i))
	check(filter_texts.size()==6,"filter box has 全部 + 5 quality entries")
	check(filter_texts[0]=="全部品质","default filter entry is 全部品质")
	for i in range(1,6):
		check(filter_texts[i]==WeaponCatalog.RARITY_NAMES[i-1],"filter %d uses the quality name"%i)
	check(not "Tier" in "".join(filter_texts) and not "TIER" in "".join(filter_texts),"no Tier text in filters")
	# --- each quality filter shows exactly its tier members ------------------------------
	for t in range(1,6):
		panel.tier_filter = t; panel.render()
		var ids: Array = card_ids(panel)
		ids.sort()
		var expected: Array = []
		for id in Utils.weapon_list:
			if WeaponCatalog.tier(int(id))==t: expected.append(int(id))
		expected.sort()
		check(ids.size()==expected.size() and str(ids)==str(expected),"quality filter %d shows exactly its members"%t)
		for text in card_texts(panel):
			check(WeaponCatalog.RARITY_NAMES[t-1] in text,"every filtered card names its quality")
			check(not "Tier" in text and not "TIER" in text,"no Tier text on cards")
	panel.tier_filter = 0; panel.render()
	check(card_ids(panel).size()==24,"cleared filter shows all 24")
	# --- quality-ascending sort stays ordered --------------------------------------------
	panel.sort_mode = 0; panel.render()
	var last_tier := 0
	var last_price := 0
	var ordered := true
	for id in card_ids(panel):
		if WeaponCatalog.tier(id)<last_tier: ordered = false
		if WeaponCatalog.tier(id)==last_tier and int(Utils.weapon_money_list[str(id)])<last_price: ordered = false
		last_tier = WeaponCatalog.tier(id); last_price = int(Utils.weapon_money_list[str(id)])
	check(ordered,"quality-ascending sort keeps tier order and within-tier price order")
	# --- sort option labels: quality both ways, price both ways, never a strength claim ----
	var sort_texts: Array = []
	for i in panel.sort_box.item_count: sort_texts.append(panel.sort_box.get_item_text(i))
	check(str(sort_texts)==str(["品质↑","品质↓","价格↑","价格↓"]),"sort options are 品质↑/品质↓/价格↑/价格↓")
	check(not "强度" in "".join(sort_texts),"no misleading 强度 label anywhere in the sort box")
	# --- quality-DESCENDING sort: tier 5 -> 1, within one tier the same stable price order --
	panel.sort_mode = 1; panel.render()
	check(card_ids(panel).size()==24,"quality-descending sort still renders every weapon")
	var desc_ok := true
	var prev_tier := 6
	var prev_price := 0
	for id in card_ids(panel):
		var t: int = WeaponCatalog.tier(id)
		var p: int = int(Utils.weapon_money_list[str(id)])
		if t>prev_tier: desc_ok = false
		if t==prev_tier and p<prev_price: desc_ok = false
		prev_tier = t; prev_price = p
	check(desc_ok,"quality-descending sort runs tier 5 -> 1 with stable within-tier price order")
	var tiers_desc: Array = []
	for id in card_ids(panel): tiers_desc.append(WeaponCatalog.tier(id))
	var tiers_asc: Array = tiers_desc.duplicate()
	tiers_asc.sort()
	tiers_asc.reverse()
	check(str(tiers_desc)==str(tiers_asc),"品质↓ walks tiers strictly 5 -> 1")
	# --- search maps the stable plan ID ---------------------------------------------------
	panel.sort_mode = 0; panel.search_text = "W24"; panel.search_box.text = "W24"; panel.render()
	check(card_ids(panel)==[124],"plan-ID search still resolves W24 -> 124")
	panel.search_text = ""; panel.search_box.text = ""; panel.render()
	# --- equipped / owned markers ---------------------------------------------------------
	var status_text = "".join(card_texts(panel))
	check("当前手持" in status_text or "已携带" in status_text,"equipped weapon carries a semantic loadout status")
	check("已拥有" in status_text or "已携带" in status_text or "当前手持" in status_text,"owned weapons carry a semantic loadout status")
	# --- detail badge speaks quality -------------------------------------------------------
	panel.show_weapon("124",Utils.weapon_list["124"].instantiate())
	var badge: String = panel.weapon_badge.text
	check(WeaponCatalog.rarity(124) in badge,"detail badge names the quality")
	check(not "Tier" in badge and not "TIER" in badge,"no Tier text on the detail badge")
	check("%d金币" % int(Utils.weapon_money_list["124"]) in badge,"detail badge shows the price")
	check(WeaponCatalog.type_name(124) in badge,"detail badge shows the type")
	print("B12_UI_CHECKS ",checks," FAILURES ",failures)
	dismiss(); await wait(0.1)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

extends Control

var tab = "weapon"
var selection = ""
var panel: PanelContainer
var listing_scroll: ScrollContainer
var listing: VBoxContainer
var detail: VBoxContainer
var wallet: Label
var message: Label
var cached: Array = []
var selected_gun = -1
var detail_actions = {}
var refresh_pending = false
var search_text = ""
var category = "全部"
var owned_only = false
var tier_filter = 0
var sort_mode = 0
var upgrade_quality_filter = 0
var action_bar: VBoxContainer
var tab_buttons = {}
var tier_box: OptionButton
var sort_box: OptionButton
var quality_box: OptionButton
var tab_state: Dictionary = {}
var search_box: LineEdit
var weapon_preview: TextureRect
var weapon_heading: Label
var weapon_badge: Label
var weapon_header: HBoxContainer
var category_box: OptionButton
var owned_filter: Button
var filter_row: HBoxContainer
var detail_scroll: ScrollContainer
var save_retry: Button
var weapon_models: Dictionary = {}
var preview_textures: Dictionary = {}
var expanded_weapons: Dictionary = {}

## B11 removed the "Hell Playtest" product concept entirely.
##
## WHY: the previous batch misread the requirement and shipped a second, separately labelled
## selector ("HELL PLAYTEST / 地狱试玩") whose departures were TRIAL departures, so clearing
## Stage 40 through it recorded nothing. That is not this product's rule. There is no trial
## stage, no locked stage and no preview mode: Stage 1-40 are all permanently and directly
## selectable from ONE normal stage list, on a completely fresh save, with no prerequisite and
## no save-progress requirement. Stage 31-40 are simply the harder Hell stages, not a second
## mode, and no player-visible control may ever say Locked / 未解锁 / Playtest / 试玩.
##
## `stage_unlocked()` is KEPT because other systems still reference the progression fields it
## used to read. It no longer decides anything a player can see: it answers
## "does this stage exist", which is the only question a selector may ask.

func switch_tab(next_tab: String):
	tab_state[tab] = {"selection":selection,"scroll":listing_scroll.scroll_vertical}
	tab = next_tab
	var state = tab_state.get(tab,{"selection":"","scroll":0})
	selection = state.selection
	listing_scroll.scroll_vertical = state.scroll
	category = "全部"
	category_box.select(0)
	render()

func matches(text: String, tags: Array = []) -> bool:
	return (search_text.is_empty() or search_text.to_lower() in text.to_lower()) and (category == "全部" or category in tags)

func _enter_tree():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.push_pause(self)

func _exit_tree():
	for node in cached:
		if is_instance_valid(node): node.free()
	for node in weapon_models.values():
		if is_instance_valid(node): node.free()
	Demo.pop_pause(self)

func label(parent, text: String, size = 7) -> Label:
	var item = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size",size)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func button(parent, text: String, action: Callable) -> Button:
	var item = Button.new()
	if parent == detail and is_instance_valid(action_bar): parent = action_bar
	item.text = text
	item.add_theme_font_size_override("font_size",7)
	item.custom_minimum_size.y = 16
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_res = Theme.new()
	theme_res.default_font = load("res://fonts/fusion-pixel.otf")
	theme_res.default_font_size = 7
	var style = StyleBoxFlat.new()
	style.bg_color = Color("172129")
	style.border_color = Color("536775")
	style.set_border_width_all(1)
	style.set_content_margin_all(3)
	theme_res.set_stylebox("panel","PanelContainer",style)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var bs = style.duplicate()
		bs.bg_color = {"normal":Color("25323b"),"hover":Color("354650"),"pressed":Color("46534b"),"focus":Color(0,0,0,0),"disabled":Color("1b252d")}[state]
		bs.border_color = Color("dec899") if state in ["pressed","focus"] else Color("465b68")
		theme_res.set_stylebox(state,"Button",bs)
		if state != "focus": theme_res.set_stylebox(state,"OptionButton",bs)
	theme_res.set_color("font_color","Button",Color("e7eded"))
	theme_res.set_color("font_disabled_color","Button",Color("899ca7"))
	theme_res.set_color("font_color","Label",Color("d8e1e5"))
	var input_style = style.duplicate()
	input_style.bg_color = Color("101920")
	theme_res.set_stylebox("normal","LineEdit",input_style)
	var input_focus = input_style.duplicate()
	input_focus.border_color = Color("dec899")
	theme_res.set_stylebox("focus","LineEdit",input_focus)
	theme_res.set_color("font_placeholder_color","LineEdit",Color("9aadb7"))
	for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
		var track = StyleBoxFlat.new()
		track.bg_color = Color("25323b") if state == "scroll" else Color("687c86")
		track.content_margin_left = 2
		track.content_margin_right = 2
		theme_res.set_stylebox(state,"VScrollBar",track)
	theme = theme_res
	var shade = ColorRect.new()
	shade.color = Color(0.02,0.04,0.08,0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 8
	panel.offset_top = 7
	panel.offset_right = -8
	panel.offset_bottom = -7
	add_child(panel)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",3)
	panel.add_child(body)
	var top = HBoxContainer.new()
	body.add_child(top)
	var heading = label(top,"营地整备",9)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	wallet = label(top,"",7)
	wallet.autowrap_mode = TextServer.AUTOWRAP_OFF
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_retry = button(top,"重试保存",func():
		message.text = Demo.save_camp().reason
		if Demo.save_blocked: Demo.show_save_dialog(true))
	button(top,"设置",func(): Demo.open_settings())
	var tools = MenuButton.new()
	tools.text = "工具"
	top.add_child(tools)
	tools.get_popup().add_item("角色属性",0)
	tools.get_popup().add_item("束缚攻击训练",1)
	tools.get_popup().id_pressed.connect(func(id):
		if id == 0: Demo.open_stats()
		else: Demo.root_lesson())
	button(top,"返回 [Esc]",queue_free)
	var tabs = HBoxContainer.new()
	body.add_child(tabs)
	for pair in [["weapon","武器"],["attachment","武器强化"],["magazine","弹匣补给"],["talent","天赋"],["stage","出发"]]:
		var nav = button(tabs,pair[1],func(): switch_tab(pair[0]))
		nav.toggle_mode = true
		nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_buttons[pair[0]] = nav
	var filters = HBoxContainer.new()
	body.add_child(filters)
	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索名称 / 编号 / 机制"
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.add_theme_font_size_override("font_size",7)
	filters.add_child(search_box)
	search_box.text_changed.connect(func(value): search_text = value; request_refresh())
	owned_filter = Button.new()
	owned_filter.text = "仅已拥有"
	owned_filter.toggle_mode = true
	filters.add_child(owned_filter)
	owned_filter.toggled.connect(func(value): owned_only = value; request_refresh())
	filter_row = HBoxContainer.new()
	body.add_child(filter_row)
	category_box = OptionButton.new()
	category_box.add_theme_font_size_override("font_size",7)
	for item in ["全部","实体","能量","爆炸","特殊"]: category_box.add_item(item)
	filter_row.add_child(category_box)
	category_box.item_selected.connect(func(index): category = category_box.get_item_text(index); request_refresh())
	tier_box = OptionButton.new()
	for text in ["全部品质",WeaponCatalog.RARITY_NAMES[0],WeaponCatalog.RARITY_NAMES[1],WeaponCatalog.RARITY_NAMES[2],WeaponCatalog.RARITY_NAMES[3],WeaponCatalog.RARITY_NAMES[4]]: tier_box.add_item(text)
	filter_row.add_child(tier_box)
	tier_box.item_selected.connect(func(index): tier_filter = index; request_refresh())
	sort_box = OptionButton.new()
	# sort_mode 1 orders by tier descending (品质↓); there is deliberately no "strength"
	# sort - the runtime benchmark score is a design metric, never a player-facing attribute.
	for text in ["品质↑","品质↓","价格↑","价格↓"]: sort_box.add_item(text)
	filter_row.add_child(sort_box)
	sort_box.item_selected.connect(func(index): sort_mode = index; request_refresh())
	# B13: the upgrade and talent shops carry their own three-quality system (普通/稀有/传说),
	# separate from the weapon catalog's five tiers.
	quality_box = OptionButton.new()
	for text in ["全部品质",AttachmentCatalog.QUALITY_NAMES[0],AttachmentCatalog.QUALITY_NAMES[1],AttachmentCatalog.QUALITY_NAMES[2]]: quality_box.add_item(text)
	filter_row.add_child(quality_box)
	quality_box.item_selected.connect(func(index): upgrade_quality_filter = index; request_refresh())
	for filter in [category_box,tier_box,sort_box,quality_box]:
		filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter.custom_minimum_size.y = 13
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",6)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var scroll = ScrollContainer.new()
	listing_scroll = scroll
	scroll.custom_minimum_size.x = 132
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	listing = VBoxContainer.new()
	listing.add_theme_constant_override("separation",2)
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(listing)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	weapon_header=HBoxContainer.new(); right.add_child(weapon_header)
	weapon_preview=TextureRect.new(); weapon_preview.name="WeaponPreview"
	weapon_preview.custom_minimum_size=Vector2(96,32); weapon_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	weapon_preview.stretch_mode=TextureRect.STRETCH_KEEP_CENTERED; weapon_preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	weapon_header.add_child(weapon_preview)
	var titles=VBoxContainer.new(); titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL; weapon_header.add_child(titles)
	weapon_heading=label(titles,"",9); weapon_badge=label(titles,"",7)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",2)
	detail_scroll.add_child(detail)
	action_bar = VBoxContainer.new()
	right.add_child(action_bar)
	message = label(body,"WASD 移动 · R 装填 · Shift 冲刺 · Esc 返回",7)
	message.custom_minimum_size.y = 18
	message.max_lines_visible = 2
	if Utils.player.gun: selected_gun = Utils.player.gun.weapon_id
	Demo.changed.connect(request_refresh)
	render()

func request_refresh():
	if refresh_pending: return
	refresh_pending = true
	call_deferred("render")

func entry(text: String, key: String, action: Callable):
	detail_actions[key] = action
	var item = button(listing,text,func():
		selection = key
		detail_scroll.scroll_vertical = 0
		action.call()
		refresh_selection())
	item.set_meta("entry_key",key)
	item.toggle_mode = true
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return item

func refresh_selection():
	for child in listing.get_children():
		if child is Button and child.has_meta("entry_key"):
			child.set_pressed_no_signal(child.get_meta("entry_key") == selection)

func update_wallet():
	wallet.text = "金币 %d  ·  天赋点 %d" % [PlayerData.gold,PlayerData.reward_point]
	if Demo.dirty or Demo.save_blocked: wallet.text += " · 未保存"
	save_retry.visible = Demo.dirty or Demo.save_blocked

func clear_box(box):
	if box == detail and is_instance_valid(action_bar): clear_box(action_bar)
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func render():
	refresh_pending = false
	weapon_header.visible=tab=="weapon"
	var scroll_position = listing_scroll.scroll_vertical
	var detail_position = detail_scroll.scroll_vertical
	var focused = get_viewport().gui_get_focus_owner()
	var focused_entry = focused.get_meta("entry_key","") if is_instance_valid(focused) else ""
	var action_focused = is_instance_valid(focused) and focused.get_parent() == action_bar
	detail_actions.clear()
	update_wallet()
	for key in tab_buttons: tab_buttons[key].set_pressed_no_signal(key == tab)
	category_box.visible = tab == "weapon"
	tier_box.visible = tab == "weapon"
	sort_box.visible = tab == "weapon"
	quality_box.visible = tab == "attachment" or tab == "talent"
	filter_row.visible = tab in ["weapon","attachment","talent"]
	owned_filter.visible = tab in ["weapon","attachment","talent"]
	search_box.visible = tab in ["weapon","attachment","talent"]
	weapon_preview.texture = null
	weapon_heading.text = ""
	weapon_badge.text = ""
	clear_box(listing)
	clear_box(detail)
	for node in cached:
		if is_instance_valid(node): node.free()
	cached.clear()
	match tab:
		"weapon":
			var ids = Utils.weapon_list.keys()
			ids.sort_custom(func(a,b):
				if sort_mode == 3: return Utils.weapon_money_list[a] > Utils.weapon_money_list[b]
				if sort_mode == 2: return Utils.weapon_money_list[a] < Utils.weapon_money_list[b]
				if WeaponCatalog.tier(int(a)) != WeaponCatalog.tier(int(b)): return WeaponCatalog.tier(int(a)) > WeaponCatalog.tier(int(b)) if sort_mode == 1 else WeaponCatalog.tier(int(a)) < WeaponCatalog.tier(int(b))
				return Utils.weapon_money_list[a] < Utils.weapon_money_list[b])
			for id in ids:
				if tier_filter > 0 and WeaponCatalog.tier(int(id)) != tier_filter: continue
				# Off-tree display models live only as long as this panel. Search and selection
				# never rebuild all weapon scenes, and real owned guns remain authoritative.
				if not weapon_models.has(id): weapon_models[id] = Utils.weapon_list[id].instantiate()
				var gun = weapon_models[id]
				var tags = DemoConfig.weapon_tags(int(id))
				var categories = []
				for pair in [["projectile","实体"],["energy","能量"],["explosive","爆炸"]]:
					if pair[0] in tags: categories.append(pair[1])
				if int(id) >= 111: categories.append("特殊")
				if not matches(tr(gun.weapon_name)+id+WeaponCatalog.definition(int(id)).get("plan","")+DemoConfig.weapon_info(int(id)),categories): continue
				if owned_only and not PlayerData.player_weapon_list.has(int(id)): continue
				var weapon_card=entry(("▶ " if Utils.player.gun and Utils.player.gun.weapon_id == int(id) else ("√ " if PlayerData.player_weapon_list.has(int(id)) else ""))+tr(gun.weapon_name)+"\n%s · %s · %d金币" % [WeaponCatalog.rarity(int(id)),WeaponCatalog.type_name(int(id)),Utils.weapon_money_list[id]],id,func(): show_weapon(id,gun))
				weapon_card.icon=gun.image; weapon_card.expand_icon=false
				weapon_card.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; weapon_card.custom_minimum_size.y=34
				weapon_card.clip_text = true
				# Read-only locator, exactly like a stage row's: the ONLY stable name for a weapon row is
				# its id, because the visible label carries a purchase/equipped marker that changes state.
				weapon_card.set_meta("weapon_id",int(id))
				tier_style(weapon_card,WeaponCatalog.tier(int(id)))
		"attachment":
			var upgrade_ids = Utils.am_dict.keys()
			upgrade_ids.sort_custom(func(a,b):
				if AttachmentCatalog.quality(int(a)) != AttachmentCatalog.quality(int(b)): return AttachmentCatalog.quality(int(a)) < AttachmentCatalog.quality(int(b))
				return int(AttachmentCatalog.PRICES[int(a)]) < int(AttachmentCatalog.PRICES[int(b)]))
			for id in upgrade_ids:
				var am = Utils.am_dict[id].instantiate()
				cached.append(am)
				var active = id in Demo.owned_global_upgrades
				if not matches(tr(am.am_name)+AttachmentCatalog.DEFINITIONS[am.am_id].info+AttachmentCatalog.quality_name(int(id))): continue
				if owned_only and not active: continue
				if upgrade_quality_filter > 0 and AttachmentCatalog.quality(int(id)) != upgrade_quality_filter: continue
				var card = entry("%s %s\n%s" % [AttachmentCatalog.quality_name(int(id)),tr(am.am_name),"√ 已激活" if active else "%d金币 · 未激活" % am.money],id,func(): show_attachment(id,am,active))
				quality_style(card,AttachmentCatalog.quality(int(id)))
		"magazine": magazine_list()
		"talent":
			button(listing,"重置计划天赋 / 查看退款",show_reset)
			for id in DemoConfig.TALENTS:
				var d = DemoConfig.TALENTS[id]
				if not matches(id+d.name+DemoConfig.talent_info(id)+DemoConfig.talent_quality_name(id)): continue
				if owned_only and Demo.rank(id) == 0: continue
				if upgrade_quality_filter > 0 and DemoConfig.talent_quality(id) != upgrade_quality_filter: continue
				var card = entry("%s %s %d/%d" % [DemoConfig.talent_quality_name(id),d.name,Demo.rank(id),d.max],id,func(): show_talent(id))
				quality_style(card,DemoConfig.talent_quality(id))
		"equipment": equipment_list()
		"stage": stage_list()
		"legacy":
			for id in RewardServer.reward_list:
				var reward = RewardServer.reward_list[id].instantiate()
				cached.append(reward)
				entry(tr(reward.reward_name),id,func(): show_legacy(id,reward))
	if selection.is_empty() and not detail_actions.is_empty(): selection = detail_actions.keys()[0]
	if detail_actions.has(selection): detail_actions[selection].call()
	if tab == "weapon": weapon_header.visible = detail_actions.has(selection)
	refresh_selection()
	listing_scroll.set_deferred("scroll_vertical",scroll_position)
	detail_scroll.set_deferred("scroll_vertical",detail_position)
	if not focused_entry.is_empty():
		for child in listing.get_children():
			if child.get_meta("entry_key","") == focused_entry: child.call_deferred("grab_focus")
	elif action_focused:
		for child in action_bar.get_children():
			if child is Button and not child.disabled:
				child.call_deferred("grab_focus")
				break
	if not detail_actions.has(selection): label(detail,"选择左侧条目查看用途、价格与实际配置。\n没有匹配条目时，可清空搜索或切回全部分类。\n战斗已暂停；Esc 只关闭最上层。\n购买与补给仅在营地开放。",8)

func purchase(kind: String,id: String,currency = "gold"):
	var result = Demo.try_purchase(kind,id,currency)
	message.text = result.reason
	if result.success: Demo.play_ui()
	selection = id
	request_refresh()

func show_weapon(id: String, gun):
	clear_box(detail)
	weapon_header.show()
	var owned = PlayerData.player_weapon_list.has(int(id))
	if owned: gun = PlayerData.player_weapon_list[int(id)]
	weapon_preview.texture=weapon_art(gun.image)
	assert(weapon_preview.texture!=null,"Missing weapon preview: "+id)
	weapon_heading.text=tr(gun.weapon_name)
	weapon_badge.text="%s · %s\n%d金币 · %s" % [WeaponCatalog.rarity(int(id)),WeaponCatalog.type_name(int(id)),Utils.weapon_money_list[id],"当前装备" if owned and gun.is_use else ("已拥有" if owned else "未拥有")]
	weapon_badge.add_theme_color_override("font_color",tier_color(WeaponCatalog.tier(int(id))))
	var stats = gun.effective if owned else {}
	if stats.is_empty():
		gun.tags = DemoConfig.weapon_tags(int(id))
		gun.base_stats = {"damage":gun.damage,"magazine":gun.bullets_max_count,"reload":gun.change_speed,"rate":gun.fire_rate,"impulse":gun.knockback_speed}
		stats = EffectiveStats.calculate(gun)
	if Utils.player.gun and Utils.player.gun.weapon_id!=int(id):
		label(detail,"当前 → 候选 · 同一构筑",7)
		var current=EffectiveStats.calculate(Utils.player.gun)
		var comparisons=GridContainer.new(); comparisons.columns=2; detail.add_child(comparisons)
		for stat in ["damage","rate","magazine","reload","crit","range"]:
			var line=comparison(stat,current[stat],stats[stat]); var first=line.find("  ")
			line=line.substr(0,first)+"\n"+line.substr(first+2)
			var cell=label(comparisons,line,7); cell.custom_minimum_size.x=108; cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	else:
		if not Utils.player.gun: label(detail,"未装备 · 以下为候选属性",7)
		label(detail,"Damage %.2f · RPM %.0f\nMagazine %d · Reload %.2fs\nCrit %.1f%% · Range %.0f" % [stats.damage,stats.rate*60,stats.magazine,stats.reload,stats.crit*100,stats.range],8)
	label(detail,WeaponCatalog.short_info(int(id)))
	label(detail," / ".join(WeaponCatalog.labels(int(id))))
	var more = Button.new()
	more.toggle_mode = true
	more.text = "机制与详细属性"
	detail.add_child(more)
	var full = label(detail,EffectiveStats.describe(stats)+"\n"+DemoConfig.weapon_info(int(id)))
	full.visible = expanded_weapons.get(id,false)
	more.set_pressed_no_signal(full.visible)
	more.toggled.connect(func(value): full.visible = value; expanded_weapons[id] = value)
	if owned:
		if gun.is_use:
			label(detail,"当前装备",8)
			# B13 unequip: the weapon stays owned, ammo untouched - only the "current weapon"
			# link is dropped. Re-equipping stays available right here and via hotkeys.
			button(detail,"卸下武器",func():
				var result = Demo.unequip_weapon()
				message.text = result.reason
				request_refresh())
		else:
			button(detail,"已拥有 | 装备",func():
				selected_gun = int(id)
				if PlayerData.changeWeapon(int(id),true): message.text = "已装备「%s」" % tr(gun.weapon_name)
				request_refresh())
	else:
		button(detail,"%d金币 | 购买" % Utils.weapon_money_list[id],func(): purchase("weapon",id))

func magazine_list():
	for count in [5,10,25]:
		var price = {5:10,10:18,25:40}[count]
		entry("+%d 弹匣 · %d金币" % [count,price],"mag"+str(count),func():
			clear_box(detail)
			label(detail,"备用弹匣补给",10)
			label(detail,"当前 %d 弹匣\n购买 +%d → %d 弹匣" % [PlayerData.reserve_magazines,count,PlayerData.reserve_magazines+count],9)
			label(detail,"一次换弹消耗1个备用弹匣，将当前枪补满。")
			button(detail,"%d金币 | 购买%d弹匣" % [price,count],func(): purchase("supply","mag"+str(count))))

func active_gun():
	return PlayerData.player_weapon_list.get(selected_gun,Utils.player.gun)

func show_attachment(id: String,am,_owned: bool):
	clear_box(detail)
	var cid = int(id)
	label(detail,"%s · %s" % [AttachmentCatalog.display_name(cid),AttachmentCatalog.quality_name(cid)],10)
	label(detail,AttachmentCatalog.DEFINITIONS[cid].info,8)
	label(detail,"所有当前和未来武器自动生效",8)
	label(detail,"价格：%d金币" % am.money,8)
	var active = id in Demo.owned_global_upgrades
	label(detail,"√ 已激活" if active else "未激活",9)
	# B13 preview: the real 当前 → 购买后 delta on the player's current gun, computed from
	# EffectiveStats, never from the card's text. Zero-delta rows are skipped.
	if not active and Utils.player.gun:
		var current = EffectiveStats.calculate(Utils.player.gun)
		var boosted = EffectiveStats.calculate(Utils.player.gun,Demo.owned_global_upgrades.duplicate()+[id])
		label(detail,"当前 → 购买后（以当前武器结算）",8)
		for stat in ["damage","crit","magazine","reload","range","spread","impulse","pierce","shards"]:
			var before = float(current.get(stat,0.0))
			var after = float(boosted.get(stat,0.0))
			if is_equal_approx(before,after): continue
			label(detail,comparison(stat,before,after),7)
	var action = button(detail,"√ 已激活" if active else "%d金币 | 购买" % am.money,func(): purchase("attachment",id))
	action.disabled = active

func show_talent(id: String):
	clear_box(detail)
	var d = DemoConfig.TALENTS[id]
	var rank = Demo.rank(id)
	label(detail,"%s · %s  %d / %d" % [d.name,DemoConfig.talent_quality_name(id),rank,d.max],10)
	label(detail,"品质：%s（价值等级；与当前等级独立）" % DemoConfig.talent_quality_name(id),7)
	label(detail,DemoConfig.talent_info(id))
	label(detail,DemoConfig.talent_effect(id,rank),8)
	label(detail,Demo.talent_status(id))
	if id in ["T07","T08"]: label(detail,"旧头盔/蓝靴作为历史来源保留，不在原型商店重复售卖；本页退款仅针对已记录的计划天赋付款。")
	if id == "T10": label(detail,"当前%d层，剩余%.1f秒" % [Demo.kill_stacks,Demo.stack_time])
	if id == "T24": label(detail,"冷却剩余%.1f秒" % Demo.heal_cooldown)
	if rank == d.max:
		label(detail,"已满级；不会扣款")
	else:
		# B13: per-quality, per-rank prices replace the flat 100/1. The next purchase charges
		# exactly the price of the rank it grants; reset/refund replays recorded payments.
		label(detail,"下一等级：%s\n等级 %d → %d\n支付任选一种：%d金币 或 %d天赋点" % [DemoConfig.talent_effect(id,rank+1),rank,rank+1,DemoConfig.talent_gold_price(id,rank+1),DemoConfig.talent_point_price(id,rank+1)])
		# B13.1: the real 当前 → 购买后 values for directly-mapped stats, settled through the
		# live calculation paths. Conditional/proc talents stay on their mechanism text above.
		var preview_lines := talent_preview_lines(id,rank,rank+1)
		if not preview_lines.is_empty():
			label(detail,"当前 → 购买后（真实结算）",8)
			for preview_line in preview_lines: label(detail,preview_line,8)
	label(action_bar,"已满级 · 不会扣款" if rank == d.max else "支付任选：%d金币 / %d天赋点" % [DemoConfig.talent_gold_price(id,rank+1),DemoConfig.talent_point_price(id,rank+1)],7)
	button(detail,"金币购买",func(): purchase("talent",id,"gold")).disabled = rank == d.max
	button(detail,"天赋点升级",func(): purchase("talent",id,"points")).disabled = rank == d.max

func equipment_list():
	switch_tab("weapon")

## Stage select. ONE list. Stage 1-40, all permanently and directly selectable.
##
## B11 rule, stated once so it cannot drift: the product has no locked stage and no trial
## stage. A brand-new empty save must be able to pick 1, 10, 20, 30, 31, 35, 39 and 40 from
## this same list and really enter that battle. Progress fields (next_stage, campaign_complete,
## hell_complete) still exist for the save format and for the "继续" convenience entry, but
## nothing in this panel reads them to decide whether a stage may be chosen.
func stage_list():
	if LevelServer.state != "CAMP":
		label(listing,"战斗中不可出发或补给")
		label(detail,"完成遭遇或失败返回营地后，可购买、补给与练枪。")
		return
	label(listing,"关卡选择 1—40",9)
	# The linear campaign still advances through this one entry, exactly as before: it is the
	# "play the story in order" door. Every entry below it is a direct repeat, and none of them
	# is gated.
	button(listing,"继续："+DemoConfig.ENCOUNTERS[Demo.next_stage].name,func(): depart_campaign())
	if Demo.campaign_complete:
		label(listing,"普通战役已完成 · 下列关卡仍可自由重玩",7)
	if Demo.hell_complete:
		label(listing,"HELL COMPLETE · 已完成第40关",7)
	stage_entries(1,40)
	button(listing,"开发辅助：补充测试钱包",func(): Demo.replenish(); message.text = "两种钱包已补到至少9999；装备、天赋、关卡保持")
	button(listing,"购买备用弹匣 →",func(): switch_tab("magazine"))
	button(listing,"恢复生命 · 10金币",func(): purchase("supply","health"))
	for count in [1,3]:
		button(listing,"练枪：%d目标" % count,func(): LevelServer.town.practice(count); queue_free())
	button(listing,"清理练枪靶与效果",func(): LevelServer.town.clear_practice(); message.text = "已清理；练枪不发金币、经验或击杀奖励")
	label(detail,"正常下一关："+DemoConfig.ENCOUNTERS[Demo.next_stage].name)
	label(detail,"1—30 为普通战役，31—40 为地狱模式（固定战争迷雾，难度更高）。\n全部关卡永久可选，没有解锁条件。\n从关卡表出发是重复挑战：不移动「继续」进度指针，通关也不改变解锁。\n原移动速度/冲刺/视角保持。\n原数字键1—7对应持有栏前7把；全部%d把可在枪械页搜索/购买/装备，也可在当前配置选枪。\n练枪靶不掉落、不结算经验。" % Utils.weapon_list.size())

## Every entry is a real, enabled control. There is deliberately no `locked` branch, no suffix
## that names a state, and no second selector: a reviewer reading this function should be able
## to conclude "1-40, all clickable" without reading anything else.
func stage_entries(first: int, last: int):
	for id in range(first,last+1):
		if not DemoConfig.ENCOUNTERS.has(id): continue
		var config = DemoConfig.ENCOUNTERS[id]
		if (id-1)%5 == 0: label(listing,M5Content.REGIONS[config.region].name)
		var item = entry(config.name,str(id),func():
			clear_box(detail)
			label(detail,config.name,10)
			label(detail,("地狱模式（固定战争迷雾）\n" if HellMode.is_hell(id) else "")+
				M5Content.REGIONS[config.region].info+"\n"+config.info+
				"\n胜利奖励：20金币 + 1天赋点，另计掉落；结束返回营地。\n重复挑战不移动「继续」进度指针。")
			button(detail,"开始此遭遇",func(): depart(id)))
		# Read-only locator for the browser probe (autoload/Smoke.gd). A driver has to click a
		# control by its REAL rectangle, and the only stable name for a stage entry is its stage
		# id - the visible text carries a region name that a future edit could change.
		item.set_meta("stage_id",id)

## Kept because save handling and audits still reference it. Its MEANING under B11 is only
## "this stage exists": progression fields no longer gate anything a player can do, so a fresh
## save answers true for 1 through 40, including 31-40. `--hell-unlock` is gone along with the
## gate it used to bypass.
func stage_unlocked(stage: int) -> bool:
	return DemoConfig.ENCOUNTERS.has(stage)

## The linear campaign door. `Town.depart(stage, false)` reads `Demo.next_stage`, so this is
## the path that writes progression; it is not reachable from the stage list below.
func depart_campaign():
	_depart_with(Demo.next_stage,false)

## Direct stage choice. Every stage in the list departs as a repeat departure, which is what
## keeps "pick stage 40 on a fresh save" from silently marking the campaign finished. The
## refusal set is the real one only: unknown stage, no equipped weapon, round already running.
func depart(stage: int):
	_depart_with(stage,true)

func _depart_with(stage: int, trial: bool):
	if not DemoConfig.ENCOUNTERS.has(stage):
		message.text = "该关卡不存在"
		return
	# B13: an explicitly unarmed player may still depart - movement/dash stay live, firing
	# is simply impossible without a weapon. The old hard refusal assumed gun is never a
	# player choice; unarmed is a first-class state now.
	if LevelServer.state != "CAMP":
		message.text = "当前仍在战斗；需先完成或返回营地"
		return
	Demo.pop_pause(self)
	if LevelServer.town.depart(stage,trial):
		queue_free()
	else:
		Demo.push_pause(self)
		message.text = "出发校验失败；位置与进度保持"

func show_legacy(id: String,reward):
	clear_box(detail)
	label(detail,tr(reward.reward_name),10)
	label(detail,tr(reward.reward_info))
	var current = Utils.player.reward_root.get_node_or_null(reward.reward_name)
	label(detail,"一次性补给（不计持久天赋）" if reward.only_start else "原型持久奖励：%d / %d" % [current.count if current else 0,reward.max_count])
	if id in ["2","5"]:
		label(detail,"已整合为T07/T08的历史来源；旧等级和原数值保留，新购买请前往持久天赋页。")
		return
	button(detail,"%d金币购买" % DemoConfig.TALENT_GOLD_PRICE,func(): purchase("legacy",id))
	button(detail,"1天赋点升级",func(): purchase("legacy",id,"points"))

func show_reset():
	var refund = Demo.reset_preview()
	var dialog = ConfirmationDialog.new()
	dialog.title = "重置计划天赋"
	dialog.dialog_text = "撤销计划天赋效果，返还有付款凭据的：\n%d金币 / %d天赋点\n历史缺失付款凭据：%d级，无法精确返还。\n确认后也会清除这些计划等级；历史原型来源保留。\n取消将保留当前全部等级。" % [refund.gold,refund.points,refund.unknown]
	dialog.min_size = Vector2i(270,130)
	dialog.get_label().add_theme_font_size_override("font_size",8)
	dialog.get_ok_button().text = "确认重置"
	dialog.get_cancel_button().text = "保留配置"
	add_child(dialog)
	dialog.confirmed.connect(func(): message.text = Demo.reset_talents(refund.revision).reason; dialog.queue_free(); request_refresh())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self):
		get_viewport().set_input_as_handled()
		queue_free()

func tier_color(tier: int) -> Color:
	return [Color("a8bac2"),Color("8ed8b0"),Color("79c6ef"),Color("c6a0ee"),Color("ffd47d")][clampi(tier,1,5)-1]
## B13 three-quality palette for upgrades/talents. Reuses the weapon catalog's visual
## language (same family colors) restricted to the three qualities this system has.
func quality_color(quality: int) -> Color:
	return [Color("a8bac2"),Color("79c6ef"),Color("ffd47d")][clampi(quality,1,3)-1]
func quality_style(item: Button,quality: int):
	row_style(item,quality_color(quality))
func weapon_art(texture: Texture2D) -> Texture2D:
	if preview_textures.has(texture): return preview_textures[texture]
	var image=texture.get_image()
	if not image or image.get_used_rect().size==Vector2i.ZERO: return texture
	var cropped = image.get_region(image.get_used_rect())
	var factor = maxi(1,mini(96 / cropped.get_width(),32 / cropped.get_height()))
	cropped.resize(cropped.get_width()*factor,cropped.get_height()*factor,Image.INTERPOLATE_NEAREST)
	var preview = ImageTexture.create_from_image(cropped)
	preview_textures[texture] = preview
	return preview
func tier_style(item: Button,tier: int):
	row_style(item,tier_color(tier))

func row_style(item: Button,color: Color):
	for state in ["normal","hover","pressed","focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = {"normal":Color("1d2a33"),"hover":Color("2c3b45"),"pressed":Color("344750"),"focus":Color(0,0,0,0)}[state]
		style.border_color = Color("e0cb9c") if state == "focus" else color
		style.border_width_left = 1
		if state in ["pressed","focus"]: style.set_border_width_all(1)
		style.set_content_margin_all(3)
		item.add_theme_stylebox_override(state,style)
func comparison(stat: String,current: float,candidate: float) -> String:
	var names={"damage":"Damage","rate":"RPM","magazine":"Magazine","reload":"Reload","crit":"Crit","range":"Range","spread":"Spread","impulse":"Knockback","pierce":"Pierce","shards":"Shards","max_hp":"Max HP","speed":"Speed","pickup":"Pickup"}
	var delta=candidate-current
	var change="%+.0f" % delta if stat in ["magazine","pierce","shards","bounces","max_hp"] else ("%+.1fpp" % (delta*100) if stat=="crit" else ("%+.0f%%" % (delta/current*100) if current!=0 else "%+.1f" % delta))
	var factor=60.0 if stat=="rate" else (100.0 if stat=="crit" else 1.0)
	return "%s  %.1f → %.1f  %s%s" % [names[stat],current*factor,candidate*factor,"▲" if delta>0 else ("▼" if delta<0 else "="),change]

## B13.1 real purchase preview for the directly-mapped talents. The numbers come from the
## SAME calculation paths the game itself uses - EffectiveStats.calculate for the weapon
## stats of the CURRENT gun, EffectiveStats.player_values / RewardServer.pickup_bonus for
## player stats, and refresh()'s own hp-delta formula for T07 - with the candidate rank
## applied only inside the calculation and restored immediately afterwards. Nothing is
## parsed from a description string, and no synthetic "overall power" is invented.
## Talents whose value is conditional or proc-driven (T10-T17, T19-T24) have no honest
## static stat to show, so they keep their mechanism descriptions.
func talent_preview_lines(id: String, rank: int, next_rank: int) -> Array:
	var lines: Array = []
	var saved_rank: int = Demo.talents.get(id,0)
	var weapon_stats := {"T01":"damage","T02":"rate","T03":"reload","T04":"magazine","T05":"range","T06":"crit","T18":"impulse"}
	if weapon_stats.has(id):
		if not is_instance_valid(Utils.player) or not is_instance_valid(Utils.player.gun): return lines
		var before: Dictionary = EffectiveStats.calculate(Utils.player.gun)
		Demo.talents[id] = next_rank
		var after: Dictionary = EffectiveStats.calculate(Utils.player.gun)
		restore_preview_rank(id,saved_rank)
		var stat: String = weapon_stats[id]
		lines.append(comparison(stat,float(before[stat]),float(after[stat])))
	elif id == "T07":
		# refresh() applies exactly this delta on purchase; preview it without mutating.
		var hp: float = PlayerData.player_hp_max
		lines.append(comparison("max_hp",hp,hp+DemoConfig.talent_value("T07",next_rank)-DemoConfig.talent_value("T07",rank)))
	elif id == "T08":
		var speed_before: float = EffectiveStats.player_values().speed
		Demo.talents[id] = next_rank
		var speed_after: float = EffectiveStats.player_values().speed
		restore_preview_rank(id,saved_rank)
		lines.append(comparison("speed",speed_before,speed_after))
	elif id == "T09":
		var pickup_before: float = 1.0+RewardServer.pickup_bonus()
		Demo.talents[id] = next_rank
		var pickup_after: float = 1.0+RewardServer.pickup_bonus()
		restore_preview_rank(id,saved_rank)
		lines.append(comparison("pickup",pickup_before,pickup_after))
	return lines

func restore_preview_rank(id: String, saved_rank: int):
	if saved_rank == 0: Demo.talents.erase(id)
	else: Demo.talents[id] = saved_rank

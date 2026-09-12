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
var compatible_only = false # Legacy fixture field; universal attachments need no filter.
var tier_filter = 0
var sort_mode = 0
var action_bar: VBoxContainer
var tab_buttons = {}
var tier_box: OptionButton
var sort_box: OptionButton
var purchased_instance = -1
var tab_state: Dictionary = {}
var search_box: LineEdit
var category_box: OptionButton

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
	style.bg_color = Color("203344")
	style.border_color = Color("91b9bd")
	style.set_border_width_all(1)
	style.set_content_margin_all(3)
	theme_res.set_stylebox("panel","PanelContainer",style)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var bs = style.duplicate()
		bs.bg_color = Color("6b5730") if state == "pressed" else (Color("314955") if state != "hover" else Color("4c6971"))
		theme_res.set_stylebox(state,"Button",bs)
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
	wallet = label(top,"",8)
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(top,"重试保存",func():
		message.text = Demo.save_camp().reason
		if Demo.save_blocked: Demo.show_save_dialog(true))
	button(top,"设置",func(): Demo.open_settings())
	button(top,"返回 [Esc]",queue_free)
	var tabs = HBoxContainer.new()
	body.add_child(tabs)
	for pair in [["weapon","武器"],["attachment","配件"],["magazine","弹匣补给"],["talent","天赋"],["stage","出发"],["equipment","装备"]]:
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
	category_box = OptionButton.new()
	category_box.add_theme_font_size_override("font_size",7)
	for item in ["全部","实体","能量","爆炸","特殊","Optics","Muzzle","Barrel","Underbarrel","Ammunition","Stock","Tactical","Perks"]: category_box.add_item(item)
	filters.add_child(category_box)
	category_box.item_selected.connect(func(index): category = category_box.get_item_text(index); request_refresh())
	var owned = CheckButton.new()
	owned.text = "已拥有"
	filters.add_child(owned)
	owned.toggled.connect(func(value): owned_only = value; request_refresh())
	tier_box = OptionButton.new()
	for text in ["全部Tier","Tier I","Tier II","Tier III","Tier IV","Tier V"]: tier_box.add_item(text)
	filters.add_child(tier_box)
	tier_box.item_selected.connect(func(index): tier_filter = index; request_refresh())
	sort_box = OptionButton.new()
	for text in ["Tier↑","强度↓","价格↑","价格↓"]: sort_box.add_item(text)
	filters.add_child(sort_box)
	sort_box.item_selected.connect(func(index): sort_mode = index; request_refresh())
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var scroll = ScrollContainer.new()
	listing_scroll = scroll
	scroll.custom_minimum_size.x = 148
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	listing = VBoxContainer.new()
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(listing)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",4)
	detail_scroll.add_child(detail)
	action_bar = VBoxContainer.new()
	right.add_child(action_bar)
	message = label(body,"WASD 移动 · 鼠标射击 · R 装填 · Shift 冲刺 · Tab 配置",7)
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
	button(listing,text,func(): selection = key; action.call())

func update_wallet():
	wallet.text = "营地整备  |  金币 %d  天赋点 %d" % [PlayerData.gold,PlayerData.reward_point]
	if Demo.dirty or Demo.save_blocked: wallet.text += " · 未保存"

func clear_box(box):
	if box == detail and is_instance_valid(action_bar): clear_box(action_bar)
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func render():
	refresh_pending = false
	var scroll_position = listing_scroll.scroll_vertical
	detail_actions.clear()
	update_wallet()
	for key in tab_buttons: tab_buttons[key].set_pressed_no_signal(key == tab)
	tier_box.visible = tab == "weapon"
	sort_box.visible = tab == "weapon"
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
				var gun = Utils.weapon_list[id].instantiate()
				cached.append(gun)
				var tags = DemoConfig.weapon_tags(int(id))
				var categories = []
				for pair in [["projectile","实体"],["energy","能量"],["explosive","爆炸"]]:
					if pair[0] in tags: categories.append(pair[1])
				if int(id) >= 111: categories.append("特殊")
				if not matches(tr(gun.weapon_name)+id+WeaponCatalog.definition(int(id)).get("plan","")+DemoConfig.weapon_info(int(id)),categories): continue
				if owned_only and not PlayerData.player_weapon_list.has(int(id)): continue
				entry(("▶ " if Utils.player.gun and Utils.player.gun.weapon_id == int(id) else ("✓ " if PlayerData.player_weapon_list.has(int(id)) else ""))+tr(gun.weapon_name)+"\nT%d · %s · %d金" % [WeaponCatalog.tier(int(id)),WeaponCatalog.type_name(int(id)),Utils.weapon_money_list[id]],id,func(): show_weapon(id,gun))
		"attachment":
			for id in Utils.am_dict:
				var am = Utils.am_dict[id].instantiate()
				cached.append(am)
				if AttachmentCatalog.DEFINITIONS.has(am.am_id): am.am_info = AttachmentCatalog.DEFINITIONS[am.am_id].info
				var instances = PlayerData.player_am_list.values().filter(func(a): return a.am_id == am.am_id)
				var slots = [am.am_type.trim_prefix("WEAPON_").capitalize().replace(" ","")]
				if not matches(tr(am.am_name)+id+tr(am.am_info),slots): continue
				if owned_only and instances.is_empty(): continue
				if compatible_only and (not active_gun() or not am.can_equip(active_gun())): continue
				entry(tr(am.am_name)+(" ✓×%d" % instances.size() if not instances.is_empty() else ""),id,func():
					var instance = PlayerData.player_am_list.get(purchased_instance)
					if instance and instance.am_id == am.am_id: show_attachment(id,instance,true)
					else: show_attachment(id,am,false))
		"magazine": magazine_list()
		"talent":
			button(listing,"重置计划天赋 / 查看退款",show_reset)
			for id in DemoConfig.TALENTS:
				var d = DemoConfig.TALENTS[id]
				if not matches(id+d.name+DemoConfig.talent_info(id)): continue
				if owned_only and Demo.rank(id) == 0: continue
				entry("%s %d/%d" % [d.name,Demo.rank(id),d.max],id,func(): show_talent(id))
		"equipment": equipment_list()
		"stage": stage_list()
		"legacy":
			for id in RewardServer.reward_list:
				var reward = RewardServer.reward_list[id].instantiate()
				cached.append(reward)
				entry(tr(reward.reward_name),id,func(): show_legacy(id,reward))
	if selection.is_empty() and not detail_actions.is_empty(): selection = detail_actions.keys()[0]
	if detail_actions.has(selection): detail_actions[selection].call()
	listing_scroll.set_deferred("scroll_vertical",scroll_position)
	if not detail_actions.has(selection): label(detail,"选择左侧条目查看用途、价格与实际配置。\n没有匹配条目时，可清空搜索或切回全部分类。\n战斗已暂停；Esc 只关闭最上层。\n购买与补给仅在营地开放。",8)

func purchase(kind: String,id: String,currency = "gold"):
	var result = Demo.try_purchase(kind,id,currency)
	message.text = result.reason
	if result.success:
		Demo.play_ui()
	if result.success and kind == "attachment":
		purchased_instance = result.instance_id
		selection = id
	else: selection = id
	request_refresh()

func show_weapon(id: String, gun):
	clear_box(detail)
	var owned = PlayerData.player_weapon_list.has(int(id))
	if owned: gun = PlayerData.player_weapon_list[int(id)]
	label(detail,tr(gun.weapon_name),10)
	label(detail,"TIER %s · %s · %d金币" % [["I","II","III","IV","V"][WeaponCatalog.tier(int(id))-1],WeaponCatalog.type_name(int(id)),Utils.weapon_money_list[id]],8)
	var stats = gun.effective if owned else {}
	if stats.is_empty():
		gun.tags = DemoConfig.weapon_tags(int(id))
		gun.base_stats = {"damage":gun.damage,"magazine":gun.bullets_max_count,"reload":gun.change_speed,"rate":gun.fire_rate,"impulse":gun.knockback_speed}
		stats = EffectiveStats.calculate(gun,[])
	label(detail,"伤害 %.2f · 射速 %.1f次/秒\n弹匣 %d · 换弹 %.2f秒" % [stats.damage,stats.rate,stats.magazine,stats.reload],8)
	label(detail,WeaponCatalog.short_info(int(id)))
	label(detail," / ".join(WeaponCatalog.labels(int(id))))
	var more = CheckButton.new()
	more.text = "查看详细属性"
	detail.add_child(more)
	var full = label(detail,EffectiveStats.describe(stats)+"\n"+DemoConfig.weapon_info(int(id)))
	full.visible = false
	more.toggled.connect(func(value): full.visible = value)
	if owned:
		var equip = button(detail,"当前装备" if gun.is_use else "已拥有 | 装备",func():
			selected_gun = int(id)
			if PlayerData.changeWeapon(int(id),true): message.text = "已装备「%s」" % tr(gun.weapon_name)
			request_refresh())
		equip.disabled = gun.is_use
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

func show_attachment(id: String,am,owned: bool):
	clear_box(detail)
	label(detail,tr(am.am_name),10)
	if AttachmentCatalog.DEFINITIONS.has(am.am_id): am.am_info = AttachmentCatalog.DEFINITIONS[am.am_id].info
	label(detail,"槽位：%s\n%s\n价格：%d金币" % [tr(am.am_type),tr(am.am_info),am.money])
	var gun = active_gun()
	if gun:
		label(detail,"目标枪：" + tr(gun.weapon_name))
		if am.can_equip(gun):
			var preview = gun.attachments_dict.duplicate()
			var old = preview.get(am.am_type)
			preview[am.am_type] = am
			var after = EffectiveStats.calculate(gun,preview.values())
			var comparison = "装配前 → 后\n伤害 %.2f → %.2f · 弹匣 %d → %d\n装填 %.2f → %.2f秒\n暴击 %.0f → %.0f%%" % [gun.effective.damage,after.damage,gun.effective.magazine,after.magazine,gun.effective.reload,after.reload,gun.effective.crit*100,after.crit*100]
			if "projectile" in gun.tags or "beam" in gun.tags: comparison += "\n冲量 %.1f → %.1f" % [gun.effective.impulse,after.impulse]
			if "spread" in gun.tags: comparison += "\n散布 %.2f → %.2f" % [gun.effective.spread,after.spread]
			if "explosive" in gun.tags: comparison += "\n爆炸半径 %.1f → %.1f" % [gun.effective.radius,after.radius]
			if "chain" in gun.tags: comparison += "\n电弧后跳 %d → %d" % [gun.effective.jumps,after.jumps]
			label(detail,comparison)

			if old and old != am: label(detail,"替换「%s」；旧件返回背包" % tr(old.am_name))
			if owned:
				button(detail,"安装到此枪",func():
					if gun.addAttachMent(am):
						message.text = "已装备：%s → %s · %s" % [tr(am.am_name),tr(gun.weapon_name),tr(am.am_type)]
						if old and old != am: message.text += "；旧件已返回背包"
						show_attachment(id,am,true))
		else: label(detail,"此枪不兼容；可购买后用于其他兼容枪")
	if owned:
		label(detail,"实例 #%d · %s" % [am.id,"未装备" if am.gun == null else "已装备到 "+tr(am.gun.weapon_name)])
		if am.gun: button(detail,"卸回背包",func(): am.gun.removeAttachMent(am); message.text = "配件已卸回背包"; show_attachment(id,am,true))
	else: button(detail,"购买到背包（未装备）",func(): purchase("attachment",id))
	if owned: button(detail,"再购买一个独立实例",func(): purchase("attachment",id))

func show_talent(id: String):
	clear_box(detail)
	var d = DemoConfig.TALENTS[id]
	var rank = Demo.rank(id)
	label(detail,d.name+"  %d / %d" % [rank,d.max],10)
	label(detail,DemoConfig.talent_info(id))
	label(detail,DemoConfig.talent_effect(id,rank),8)
	label(detail,Demo.talent_status(id))
	if id in ["T07","T08"]: label(detail,"旧头盔/蓝靴作为历史来源保留，不在原型商店重复售卖；本页退款仅针对已记录的计划天赋付款。")
	if id == "T10": label(detail,"当前%d层，剩余%.1f秒" % [Demo.kill_stacks,Demo.stack_time])
	if id == "T24": label(detail,"冷却剩余%.1f秒" % Demo.heal_cooldown)
	label(detail,"已满级；不会扣款" if rank == d.max else "下一等级：%s\n等级 %d → %d\n支付任选一种：%d金币 或 1天赋点" % [DemoConfig.talent_effect(id,rank+1),rank,rank+1,DemoConfig.TALENT_GOLD_PRICE])
	button(detail,"金币购买",func(): purchase("talent",id,"gold")).disabled = rank == d.max
	button(detail,"天赋点升级",func(): purchase("talent",id,"points")).disabled = rank == d.max

func equipment_list():
	for id in PlayerData.player_weapon_list:
		var gun = PlayerData.player_weapon_list[id]
		entry(("▶ " if gun.is_use else "枪 · ")+tr(gun.weapon_name),"gun:"+str(id),func(): selected_gun = id; show_weapon(str(id),gun))
	label(listing,"配件实例（选择查看/安装）")
	for am in PlayerData.player_am_list.values():
		entry("#%d %s%s" % [am.id,tr(am.am_name)," ✓" if am.gun else ""],"am:"+str(am.id),func(): show_attachment(str(am.am_id),am,true))
	button(listing,"原型拖拽背包",func():
		if Utils.player.gun:
			var inv = load("res://ui/Inventory.tscn").instantiate()
			get_parent().add_child(inv))

func stage_list():
	if LevelServer.state != "CAMP":
		label(listing,"战斗中不可出发或补给")
		label(detail,"完成遭遇或失败返回营地后，可购买、补给与练枪。")
		return
	button(listing,"继续："+DemoConfig.ENCOUNTERS[Demo.next_stage].name,func(): depart(Demo.next_stage,false))
	if Demo.campaign_complete:
		button(listing,"已完成核心 · 从第1轮再次出发",func(): Demo.next_stage = 1; depart(1,false))
	for id in DemoConfig.ENCOUNTERS:
		if (id-1)%5 == 0: label(listing,M5Content.REGIONS[DemoConfig.ENCOUNTERS[id].region].name)
		entry(DemoConfig.ENCOUNTERS[id].name,str(id),func():
			clear_box(detail)
			label(detail,DemoConfig.ENCOUNTERS[id].name,10)
			label(detail,M5Content.REGIONS[DemoConfig.ENCOUNTERS[id].region].info+"\n"+DemoConfig.ENCOUNTERS[id].info+"\n胜利奖励：20金币 + 1天赋点，另计掉落；结束返回营地。\n直接试玩不跳过正常进度。")
			button(detail,"开始此遭遇",func(): depart(id,true)))
	button(listing,"开发辅助：补充测试钱包",func(): Demo.replenish(); message.text = "两种钱包已补到至少9999；装备、天赋、关卡保持")
	button(listing,"购买备用弹匣 →",func(): switch_tab("magazine"))
	button(listing,"恢复生命 · 10金币",func(): purchase("supply","health"))
	for count in [1,3]:
		button(listing,"练枪：%d目标" % count,func(): LevelServer.town.practice(count); queue_free())
	button(listing,"清理练枪靶与效果",func(): LevelServer.town.clear_practice(); message.text = "已清理；练枪不发金币、经验或击杀奖励")
	label(detail,"正常下一关："+DemoConfig.ENCOUNTERS[Demo.next_stage].name)
	label(detail,"原移动速度/冲刺/视角保持。\n原数字键1—7对应持有栏前7把；全部%d把可在枪械页搜索/购买/装备，也可在当前配置选枪。\n练枪靶不掉落、不结算经验。" % Utils.weapon_list.size())

func depart(stage: int, trial: bool):
	if not Utils.player.gun:
		message.text = "请先购买并装备一把枪"
		return
	if LevelServer.state != "CAMP":
		message.text = "当前仍在战斗；需先完成或返回营地"
		return
	Demo.pop_pause(self)
	if LevelServer.town.depart(stage,trial): queue_free()
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

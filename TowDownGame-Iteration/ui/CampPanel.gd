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
		bs.bg_color = Color("314955") if state != "hover" else Color("4c6971")
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
	for pair in [["weapon","枪械"],["attachment","配件商店"],["talent","持久天赋"],["equipment","当前配置"],["stage","出发/补给"],["legacy","原型奖励"]]:
		button(tabs,pair[1],func(): tab = pair[0]; selection = ""; listing_scroll.scroll_vertical = 0; render())
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
	var detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",4)
	detail_scroll.add_child(detail)
	message = label(body,"WASD 移动 · 鼠标射击 · R 装填 · Shift 冲刺 · Tab 配置",7)
	message.custom_minimum_size.y = 25
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
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func render():
	refresh_pending = false
	var scroll_position = listing_scroll.scroll_vertical
	detail_actions.clear()
	update_wallet()
	clear_box(listing)
	clear_box(detail)
	for node in cached:
		if is_instance_valid(node): node.free()
	cached.clear()
	match tab:
		"weapon":
			var ids = Utils.weapon_list.keys()
			ids.sort_custom(func(a,b): return int(a)<int(b))
			for id in ids:
				var gun = Utils.weapon_list[id].instantiate()
				cached.append(gun)
				entry(("▶ " if Utils.player.gun and Utils.player.gun.weapon_id == int(id) else ("✓ " if PlayerData.player_weapon_list.has(int(id)) else ""))+tr(gun.weapon_name),id,func(): show_weapon(id,gun))
		"attachment":
			for id in Utils.am_dict:
				var am = Utils.am_dict[id].instantiate()
				cached.append(am)
				entry(tr(am.am_name),id,func(): show_attachment(id,am,false))
		"talent":
			for id in DemoConfig.TALENTS:
				var d = DemoConfig.TALENTS[id]
				entry("%s %d/%d" % [d.name,Demo.rank(id),d.max],id,func(): show_talent(id))
		"equipment": equipment_list()
		"stage": stage_list()
		"legacy":
			for id in RewardServer.reward_list:
				var reward = RewardServer.reward_list[id].instantiate()
				cached.append(reward)
				entry(tr(reward.reward_name),id,func(): show_legacy(id,reward))
	if detail_actions.has(selection): detail_actions[selection].call()
	listing_scroll.set_deferred("scroll_vertical",scroll_position)
	if selection == "": label(detail,"选择左侧条目查看用途、价格与实际配置。\n\n战斗已暂停；Esc 只关闭最上层。\n购买与补给仅在营地开放。\n装备和天赋不会因失败丢失。",8)

func purchase(kind: String,id: String,currency = "gold"):
	var result = Demo.try_purchase(kind,id,currency)
	message.text = result.reason
	if result.success:
		Demo.play_ui()
	if result.success and kind == "attachment":
		tab = "equipment"
		selection = "am:"+str(result.instance_id)
	else: selection = id
	request_refresh()

func show_weapon(id: String, gun):
	clear_box(detail)
	label(detail,tr(gun.weapon_name),10)
	var image = TextureRect.new()
	image.texture = gun.image
	image.custom_minimum_size = Vector2(40,22)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(image)
	var description = DemoConfig.weapon_info(int(id))
	label(detail,description)
	if PlayerData.player_weapon_list.has(int(id)):
		gun = PlayerData.player_weapon_list[int(id)]
		label(detail,EffectiveStats.describe(gun.effective))
		label(detail,"已装备" if gun.is_use else "已拥有但未装备")
		button(detail,"装备到手中",func():
			selected_gun = int(id)
			if PlayerData.changeWeapon(int(id),true): message.text = "已装备「%s」" % tr(gun.weapon_name)
			else: message.text = "切枪去抖中或角色无法装备，请稍后重试"
			request_refresh())
	else:
		label(detail,"基础武器伤害 %.2f · %.2f次/秒\n弹匣 %d · 装填 %.2f秒\n价格：%d金币" % [gun.damage,gun.fire_rate,gun.bullets_max_count,gun.change_speed,Utils.weapon_money_list[id]])
		button(detail,"金币购买",func(): purchase("weapon",id))

func active_gun():
	return PlayerData.player_weapon_list.get(selected_gun,Utils.player.gun)

func show_attachment(id: String,am,owned: bool):
	clear_box(detail)
	label(detail,tr(am.am_name),10)
	label(detail,"槽位：%s\n%s\n价格：%d金币" % [tr(am.am_type),tr(am.am_info),am.money])
	var compatible = []
	for key in Utils.weapon_list:
		var candidate = Utils.weapon_list[key].instantiate()
		candidate.tags = DemoConfig.weapon_tags(int(key))
		if am.can_equip(candidate): compatible.append(tr(candidate.weapon_name))
		candidate.free()
	label(detail,"兼容："+" / ".join(compatible))
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

func show_talent(id: String):
	clear_box(detail)
	var d = DemoConfig.TALENTS[id]
	var rank = Demo.rank(id)
	label(detail,d.name+"  %d / %d" % [rank,d.max],10)
	label(detail,d.info)
	var cumulative = {"T01":"累计伤害 +%d%%" % (rank*8),"T03":"累计装填 -%d%%" % (rank*5),"T04":"累计弹匣 +%d%%" % (rank*10),"T10":"当前%d层，剩余%.1f秒；每层 +%d%%" % [Demo.kill_stacks,Demo.stack_time,rank*3],"T16":"已解锁" if rank else "未解锁","T24":"每次回复 %.2f；冷却剩余%.1f秒" % [rank*0.15,Demo.heal_cooldown]}
	label(detail,cumulative[id],8)
	label(detail,"已满级；不会扣款" if rank == d.max else "下一等级 %d → %d；按上述每级数值增加\n支付任选一种：%d金币 或 1天赋点" % [rank,rank+1,DemoConfig.TALENT_GOLD_PRICE])
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
	button(listing,"继续下一关",func(): depart(Demo.next_stage,false))
	for id in DemoConfig.ENCOUNTERS:
		entry(DemoConfig.ENCOUNTERS[id].name,str(id),func():
			clear_box(detail)
			label(detail,DemoConfig.ENCOUNTERS[id].name,10)
			label(detail,DemoConfig.ENCOUNTERS[id].info+"\n胜利奖励：20金币 + 1天赋点，另计掉落；结束返回营地。\n直接试玩不跳过正常进度。")
			button(detail,"开始此遭遇",func(): depart(id,true)))
	button(listing,"试玩补充资源",func(): Demo.replenish(); message.text = "两种钱包已补到至少9999；装备、天赋、关卡保持")
	button(listing,"补充300备弹 · 10金币",func(): purchase("supply","ammo"))
	button(listing,"恢复生命 · 10金币",func(): purchase("supply","health"))
	for count in [1,3]:
		button(listing,"练枪：%d目标" % count,func(): LevelServer.town.practice(count); queue_free())
	button(listing,"清理练枪靶与效果",func(): LevelServer.town.clear_practice(); message.text = "已清理；练枪不发金币、经验或击杀奖励")
	label(detail,"正常下一关："+DemoConfig.ENCOUNTERS[Demo.next_stage].name)
	label(detail,"原移动速度/冲刺/视角保持。\n原数字键1—7对应持有栏前7把；全部13把可在枪械页购买/装备，也可在当前配置选枪。\n练枪靶不掉落、不结算经验。")

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
	button(detail,"%d金币购买" % DemoConfig.TALENT_GOLD_PRICE,func(): purchase("legacy",id))
	button(detail,"1天赋点升级",func(): purchase("legacy",id,"points"))

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self):
		get_viewport().set_input_as_handled()
		queue_free()

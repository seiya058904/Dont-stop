extends Control
var snapshot: Dictionary
var values: Dictionary = {}
var source_buttons: Dictionary = {}
var body: VBoxContainer
var details: VBoxContainer
var listing: VBoxContainer
var selected = "damage"
var tab = "build"
var overview: VBoxContainer
var columns: HBoxContainer
var owned_icons: Dictionary = {}
const CATEGORY = {"upgrade":"武器强化", "talent":"天赋", "reward":"原型奖励", "base":"基础武器", "level":"等级成长", "legacy":"基础成长", "condition":"条件效果", "history":"历史成长", "rule":"边界规则"}
const LEDGER = preload("res://game/config/StatLedger.gd")
const NAMES = {"damage":"伤害","crit":"暴击率","rate":"射速","magazine":"弹匣","reload":"换弹秒数","range":"有效射程","spread":"散布倍率","impulse":"普通敌人击退","projectile_count":"每次发射数量","shards":"后继裂片数","pierce":"额外贯穿","speed":"移动速度","max_hp":"最大生命","pickup":"拾取范围"}
func _enter_tree():
	process_mode=Node.PROCESS_MODE_ALWAYS; Demo.push_pause(self)
func _exit_tree(): Demo.pop_pause(self)
func label(parent,text_value: String,font_size=7) -> Label:
	var node=Label.new(); node.text=text_value; node.add_theme_font_size_override("font_size",font_size); node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(node); return node
func button(parent,text_value: String,action: Callable) -> Button:
	var node=Button.new(); node.text=text_value; node.custom_minimum_size.y=17; node.pressed.connect(action); parent.add_child(node); return node
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t=Theme.new(); t.default_font=load("res://fonts/fusion-pixel.otf"); t.default_font_size=7; theme=t
	var shade=ColorRect.new(); shade.color=Color("14232e"); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	body=VBoxContainer.new(); body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); body.offset_left=10; body.offset_top=7; body.offset_right=-10; body.offset_bottom=-7; add_child(body)
	var header=HBoxContainer.new(); body.add_child(header)
	var title=label(header,"角色属性 · 来源与最终值"); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(header,"返回 [Esc]",queue_free)
	var tabs=HBoxContainer.new(); body.add_child(tabs)
	for pair in [["build","我的构筑"],["player","玩家"],["weapon","当前武器"],["effects","条件 / 效果"],["level","等级说明"]]: button(tabs,pair[1],func(): tab=pair[0]; render())
	overview=VBoxContainer.new(); overview.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(overview)
	columns=HBoxContainer.new(); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(columns)
	for side in 2:
		var scroll=ScrollContainer.new(); scroll.custom_minimum_size.x=177 if side==0 else 195; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; columns.add_child(scroll)
		var box=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(box)
		if side==0: listing=box
		else: details=box
	render()
func render():
	for parent in [listing,details,overview]:
		for child in parent.get_children(): parent.remove_child(child); child.queue_free()
	source_buttons.clear(); values.clear()
	if not Utils.player.gun:
		label(listing,"装备武器后可查看完整属性。"); return
	snapshot=EffectiveStats.inspect(Utils.player.gun)
	overview.visible=tab=="build"; columns.visible=tab!="build"
	if tab=="build": render_build(); return
	var p=snapshot.player; var gun=Utils.player.gun
	if tab=="level": label(listing,PlayerData.PROGRESSION.help_text()); label(details,"当前 Lv.%d\nEXP %.1f / %.1f\n每次有效击杀获得1经验。" % [p.level,p.exp,p.exp_max]); return
	if tab=="effects":
		for row in snapshot.conditions: button(listing,row.name,func(): show_effect(row))
		for row in preload("res://game/config/CombatStatus.gd").entries(): label(details,row.name+"："+row.value+"\n来源："+row.source+"\n"+row.info)
		return
	var stats=["damage","crit","rate","magazine","reload","range","projectile_count","spread","impulse","shards","pierce"]
	if tab=="player":
		label(listing,"Lv.%d · EXP %.1f / %.1f\n生命 %.1f / %.1f\n奖励点 %d" % [p.level,p.exp,p.exp_max,p.hp,p.max_hp,p.points])
		label(listing,"普通入伤 ×%.4f\nBoss普通入伤 ×%.4f\n百分比大招独立，再经过护盾/减伤。" % [p.normal_incoming,p.boss_incoming])
		label(listing,"护盾："+(("就绪" if p.shield_cooldown<=0 else "%.1fs" % p.shield_cooldown) if p.shield_unlocked else "未解锁"))
		label(listing,"吸附半径 ×%.2f\n备用弹匣 %d" % [p.pickup_multiplier,p.reserve_magazines])
		stats=["max_hp","speed","damage","crit","pickup"]
	else:
		var preview=TextureRect.new(); preview.texture=gun.image; preview.custom_minimum_size=Vector2(120,30); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; listing.add_child(preview)
		label(listing,tr(gun.weapon_name)+" · Tier "+str(WeaponCatalog.tier(gun.weapon_id)))
		label(listing,"弹药 %d / %d · RPM %.1f\n%s" % [gun.bullets_count,snapshot.weapon.magazine,snapshot.weapon.rpm,EffectiveStats.damage_unit(gun.effective)])
	for stat in stats:
		var value=p.get(stat,snapshot.weapon.get(stat,0)); values[stat]=value
		var formatted="%.1f%%" % (value*100) if stat=="crit" else "%.3f" % value
		source_buttons[stat]=button(listing,NAMES[stat]+"  "+formatted+"  ›",func(): selected=stat; show_sources(stat))
	show_sources(selected if selected in stats else stats[0])
func show_sources(stat: String):
	for child in details.get_children(): child.free()
	label(details,NAMES[stat]+" · 来源")
	for kind in CATEGORY:
		var rows=snapshot.ledger.ordered(stat).filter(func(r): return r.source_type==kind and meaningful(r))
		if rows.is_empty(): continue
		var reveal=VBoxContainer.new()
		button(details,CATEGORY[kind]+" · "+summary(rows)+"  ›",func(): reveal.visible=not reveal.visible)
		details.add_child(reveal); reveal.visible=false
		for row in rows: label(reveal,LEDGER.text(row))
	label(details,"最终："+str(values.get(stat,snapshot.weapon.get(stat,0))))
	if tab=="weapon": label(details,DemoConfig.weapon_info(Utils.player.gun.weapon_id)+"\n暴击、目标护甲、猎手与命中特效另行结算，详见条件/效果。")
func show_effect(row: Dictionary):
	for child in details.get_children(): child.free()
	label(details,row.name+"\n来源："+row.source+"\n"+row.info+"\n"+row.status)
func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self): get_viewport().set_input_as_handled(); queue_free()

func meaningful(row: Dictionary) -> bool:
	if not (row.value is float or row.value is int): return true
	return not is_equal_approx(float(row.value),1.0 if row.operation=="multiplier" else 0.0)

func summary(rows: Array) -> String:
	var groups={}
	for row in rows:
		if not row.active or not meaningful(row): continue
		var key=row.stat_id+"/"+row.operation
		if not groups.has(key): groups[key]=row.duplicate()
		elif row.operation=="multiplier": groups[key].value*=row.value
		elif row.value is float or row.value is int: groups[key].value+=row.value
	var parts=PackedStringArray()
	for row in groups.values():
		if not meaningful(row): continue
		var copy=row.duplicate(); copy.source_name=NAMES.get(row.stat_id,row.stat_id); copy.condition=""
		parts.append(LEDGER.text(copy).replace(" · 生效","").replace("（同组相加）",""))
	return "\n".join(parts) if not parts.is_empty() else "无常驻数值增益"

func make_owned(grid,kind: String,id: String,picture: Texture2D,title: String,info: String):
	var item=preload("res://ui/BuildIcon.gd").new()
	# Product decision: in this panel the weapon upgrade and talent entries are
	# text only. The icon is removed together with the space it reserved, rather
	# than scaled to match - and every other entry kind keeps its icon.
	if kind in ["upgrade","talent"]:
		item.text_only=true
		picture=null
	item.picture=picture; item.description=title+"\n来源："+CATEGORY[kind]+"\n"+info
	var rows=snapshot.ledger.rows.filter(func(r): return (r.source_type==kind or (kind=="talent" and r.source_type=="condition")) and r.source_id==id and meaningful(r))
	for row in rows: item.description+="\n"+NAMES.get(row.stat_id,row.stat_id)+"："+LEDGER.text(row)
	if kind=="upgrade":
		item.description+="\n当前基础发射贡献（移除此强化的差值；交互项不可直接相加）：" if not snapshot.upgrade_deltas[id].is_empty() else "\n条件效果：按上述触发条件结算，不计为常驻属性。"
		for stat in snapshot.upgrade_deltas[id]:
			var value=snapshot.upgrade_deltas[id][stat]
			item.description+="\n"+NAMES[stat]+(" %+.1fpp" % (value*100) if stat=="crit" else " %+.2f" % value)
	var tooltip=item.description
	if kind!="reward":
		item.text=title+"\n"+(info.split("。",false)[0].left(12) if kind=="upgrade" else ("常驻 · 已激活" if id in ["T01","T02","T03","T04","T05","T06","T07","T08","T09","T18"] else Demo.talent_status(id).left(12))); item.add_theme_font_size_override("font_size",7); item.custom_minimum_size=Vector2(113,27)
	item.pressed.connect(func():
		tab="weapon"; render(); show_effect({"name":title,"source":CATEGORY[kind],"info":tooltip,"status":""}))
	owned_icons[kind+"/"+id]=item; grid.add_child(item)

func render_build():
	owned_icons.clear()
	label(overview,"我的力量来自哪里？ · 点击最终值查看来源",8)
	var finals=GridContainer.new(); finals.columns=4; overview.add_child(finals)
	for stat in ["damage","crit","rate","magazine","reload","range","max_hp","speed","impulse"]:
		var value=snapshot.player.get(stat,snapshot.weapon.get(stat,0)); values[stat]=value
		var text_value="%.1f" % value
		if stat=="crit": text_value="%.1f%%" % (value*100)
		if stat=="rate": text_value="%.0f RPM" % snapshot.weapon.rpm
		var node=button(finals,NAMES[stat]+" "+text_value,func(): tab="player" if stat in ["max_hp","speed"] else "weapon"; selected=stat; render())
		node.size_flags_horizontal=Control.SIZE_EXPAND_FILL; source_buttons[stat]=node
		if stat=="impulse": node.hide()
	var cards=HBoxContainer.new(); cards.size_flags_vertical=Control.SIZE_EXPAND_FILL; overview.add_child(cards)
	for kind in ["upgrade","talent","reward"]:
		var card=VBoxContainer.new(); card.custom_minimum_size.x=124; card.size_flags_horizontal=Control.SIZE_EXPAND_FILL; cards.add_child(card)
		var count=Demo.owned_global_upgrades.size() if kind=="upgrade" else (Demo.talents.values().filter(func(r): return r>0).size() if kind=="talent" else Utils.player.reward_root.get_child_count())
		label(card,CATEGORY[kind]+" · %d项" % count,8)
		var total_text=summary(snapshot.ledger.rows.filter(func(r): return r.source_type==kind and r.condition.is_empty()))
		var total=label(card,total_text); total.max_lines_visible=3; total.tooltip_text=total_text
		button(card,CATEGORY[kind]+"合计 / 特殊效果 ›",func(): show_category(kind))
		var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; card.add_child(scroll)
		var content=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(content)
		var grid=GridContainer.new(); grid.columns=4 if kind=="reward" else 1; content.add_child(grid)
		if kind=="upgrade":
			for id in Demo.owned_global_upgrades:
				var am=Utils.am_dict[str(id)].instantiate()
				make_owned(grid,kind,str(id),am.am_image,tr(am.am_name),AttachmentCatalog.DEFINITIONS[int(id)].info)
				am.free()
		elif kind=="talent":
			for id in Demo.talents:
				if Demo.rank(id)<=0: continue
				var info=DemoConfig.talent_effect(id,Demo.rank(id))+"\n"+DemoConfig.talent_info(id)+"\n"+Demo.talent_status(id)
				if id=="T10": info+="\n当前%d层 · 剩余%.1fs" % [Demo.kill_stacks,Demo.stack_time]
				make_owned(grid,kind,id,load("res://Sprites/All_Icons/Blue Crystal.png"),DemoConfig.TALENTS[id].name+" Lv.%d" % Demo.rank(id),info)
		else:
			for reward in Utils.player.reward_root.get_children():
				make_owned(grid,kind,str(reward.id),reward.reward_image,tr(reward.reward_name),"当前 %d / %d 层\n" % [reward.count,reward.max_count]+tr(reward.reward_info))

		var special=button(content,"条件效果 / 特殊效果  ›",func(): tab="effects"; render())
		special.tooltip_text="触发效果单独计算，不计为永久属性。"
	label(overview,"基础成长与边界规则见最终值详情 · % / pp / × 分别表示百分比、百分点、倍率",6)

func show_category(kind: String):
	tab="weapon"; render()
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	label(details,CATEGORY[kind]+"合计",8)
	label(details,summary(snapshot.ledger.rows.filter(func(r): return r.source_type==kind and r.condition.is_empty())))
	label(details,"条件效果 / 特殊效果",8)
	for row in snapshot.ledger.rows:
		if (row.source_type==kind or (kind=="talent" and row.source_type=="condition" and row.source_id in Demo.talents)) and not row.condition.is_empty() and meaningful(row): label(details,LEDGER.text(row)+(" · ACTIVE" if row.active else " · INACTIVE"))
	for row in snapshot.conditions:
		if (kind=="talent" and row.source=="天赋") or (kind=="reward" and row.source.begins_with("奖励")): label(details,row.name+"\n"+row.info+"\n"+row.status)

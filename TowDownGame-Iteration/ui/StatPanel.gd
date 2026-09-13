extends Control
var snapshot: Dictionary
var values: Dictionary = {}
var source_buttons: Dictionary = {}
var body: VBoxContainer
var details: VBoxContainer
var listing: VBoxContainer
var selected = "damage"
var tab = "weapon"
const LEDGER = preload("res://game/config/StatLedger.gd")
const NAMES = {"damage":"下一次基础发射伤害","crit":"暴击率","rate":"实际发射频率","magazine":"弹匣容量","reload":"装填秒数","range":"有效射程","spread":"散布倍率","impulse":"普通敌人击退","projectile_count":"每次发射数量","shards":"后继裂片数","pierce":"额外贯穿","speed":"移动速度","max_hp":"最大生命"}
func _enter_tree():
	process_mode=Node.PROCESS_MODE_ALWAYS; Demo.push_pause(self)
func _exit_tree(): Demo.pop_pause(self)
func label(parent,text_value: String) -> Label:
	var node=Label.new(); node.text=text_value; node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(node); return node
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
	for pair in [["player","玩家"],["weapon","当前武器"],["effects","条件 / 效果"],["level","等级说明"]]: button(tabs,pair[1],func(): tab=pair[0]; render())
	var columns=HBoxContainer.new(); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(columns)
	for side in 2:
		var scroll=ScrollContainer.new(); scroll.custom_minimum_size.x=177 if side==0 else 195; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; columns.add_child(scroll)
		var box=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(box)
		if side==0: listing=box
		else: details=box
	render()
func render():
	for parent in [listing,details]:
		for child in parent.get_children(): child.free()
	source_buttons.clear(); values.clear()
	if not Utils.player.gun:
		label(listing,"装备武器后可查看完整属性。"); return
	snapshot=EffectiveStats.inspect(Utils.player.gun)
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
		stats=["max_hp","speed","damage","crit"]
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
	for row in snapshot.ledger.ordered(stat): label(details,LEDGER.text(row))
	label(details,"最终："+str(values.get(stat,snapshot.weapon.get(stat,0))))
	if tab=="weapon": label(details,DemoConfig.weapon_info(Utils.player.gun.weapon_id)+"\n暴击、目标护甲、猎手与命中特效另行结算，详见条件/效果。")
func show_effect(row: Dictionary):
	for child in details.get_children(): child.free()
	label(details,row.name+"\n来源："+row.source+"\n"+row.info+"\n"+row.status)
func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self): get_viewport().set_input_as_handled(); queue_free()

extends Label
var elapsed = 0.0
func _ready():
	position = Vector2(8,174)
	size = Vector2(345,20)
	add_theme_font_override("font",load("res://fonts/fusion-pixel.otf"))
	add_theme_font_size_override("font_size",6)
	add_theme_color_override("font_shadow_color",Color.BLACK)
	add_theme_constant_override("shadow_offset_x",1)
	add_theme_constant_override("shadow_offset_y",1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Demo.changed.connect(refresh)

func refresh():
	update_text()

func _process(delta):
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0
	update_text()

func update_text():
	if not Utils.player.gun:
		text = "Tab 配置 · 枪械页可找到全部24把武器"
		return
	var gun = Utils.player.gun
	var names = []
	for am in gun.attachments_dict.values(): names.append(tr(am.am_name))
	text = "%s · %d / %d MAGS | 配件 %s · Tab全部武器/详情\n火力%d 装填%d 携弹%d | 连杀 %d层 %.1fs · 爆破%s 修复%d" % [tr(gun.weapon_name),gun.bullets_count,PlayerData.reserve_magazines,("无" if names.is_empty() else " / ".join(names.slice(0,2))),Demo.rank("T01"),Demo.rank("T03"),Demo.rank("T04"),Demo.kill_stacks,maxf(0,Demo.stack_time),"开" if Demo.rank("T16") else "关",Demo.rank("T24")]

	if Demo.rank("T19") > 0: text += " · 盾%.1fs" % Demo.cooldown("T19")
	if Demo.crowd_active: text += " · 火网生效"
	if LevelServer.state == "CAMP":
		for target in get_tree().get_nodes_in_group("monsters"):
			if target.training:
				text += "\n练枪 · "+EffectiveStats.damage_unit(gun.effective)+" · 不结算奖励；Tab清理"
				break

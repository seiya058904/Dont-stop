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
func _process(delta):
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0
	if not Utils.player.gun: return
	var gun = Utils.player.gun
	var names = []
	for am in gun.attachments_dict.values(): names.append(tr(am.am_name))
	text = "%s · %d/%d | 配件 %s · Tab详情\n火力%d 装填%d 携弹%d | 连杀 %d层 %.1fs · 爆破%s 修复%d" % [tr(gun.weapon_name),gun.bullets_count,gun.bullets_max_count,("无" if names.is_empty() else " / ".join(names)),Demo.rank("T01"),Demo.rank("T03"),Demo.rank("T04"),Demo.kill_stacks,maxf(0,Demo.stack_time),"开" if Demo.rank("T16") else "关",Demo.rank("T24")]

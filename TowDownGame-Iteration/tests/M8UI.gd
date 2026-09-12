extends "res://tests/M8Runtime.gd"
func texts(node) -> String:
	var result = ""
	if node is Label or node is Button: result += node.text+"\n"
	for child in node.get_children(): result += texts(child)
	return result
func _ready():
	await boot()
	check(LevelServer.town.camp_prompt.text=="按 E 打开营地","camp has E prompt")
	check(not "买枪" in texts(LevelServer.town.get_node("CanvasLayer")),"no permanent purchase row")
	var event = InputEventAction.new(); event.action = "e"; event.pressed = true
	LevelServer.town._unhandled_input(event); await wait(0.1)
	var panel = Demo.ui
	check(is_instance_valid(panel) and panel.tab_buttons.size()==5,"E opens five-category menu")
	panel.switch_tab("attachment"); await wait(0.1)
	for id in Utils.am_dict:
		panel.selection = str(id); panel.render()
		var content = texts(panel)
		check("未激活" in content and not "安装" in content and not "槽位" in content and not "实例" in content and not "兼容" in content,"simple upgrade UI "+str(id))
		var buttons = panel.action_bar.get_children().filter(func(n): return n is Button)
		check(buttons.size()==1 and not buttons[0].disabled,"one purchase action "+str(id))
		buttons[0].pressed.emit(); await wait(0.03)
		check(panel.action_bar.get_child(0).disabled and panel.action_bar.get_child(0).text=="✓ 已激活","activation immediately disables button "+str(id))
	panel.switch_tab("weapon"); check(panel.detail_actions.size()==24,"24 weapon shop entries")
	panel.purchase("weapon","0"); panel.purchase("weapon","124"); await wait(0.1)
	panel.switch_tab("magazine"); var reserve = PlayerData.reserve_magazines; panel.purchase("supply","mag10")
	check(PlayerData.reserve_magazines==reserve+10,"magazine purchase")
	panel.switch_tab("talent"); panel.purchase("talent","T01","points"); check(Demo.rank("T01")==1,"talent purchase")
	dismiss(); await wait(0.1)
	check(not get_tree().paused,"close restores play")
	print("M8 UI SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

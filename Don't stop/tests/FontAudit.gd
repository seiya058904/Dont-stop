extends Node

## Runtime font / text audit for every product screen.
##
## Why this exists: the Web export has no OS font fallback, so any codepoint the
## effective font cannot draw becomes a hex code box (TextServer::draw_hex_code_box)
## instead of a character. Guessing from the .import files is not evidence, so this
## walks the real instantiated UI, resolves the font each control actually renders
## with (theme override -> LabelSettings -> theme chain -> project default), follows
## that font's fallback chain, and reports every character it cannot cover.
##
## It also flags translation keys / internal ids that leaked into visible text.
##
## Usage: godot --headless --path <project> res://tests/FontAudit.tscn
## Output: FONT_AUDIT_* lines on stdout (machine readable) + a JSON blob.

var missing_rows: Array = []
var leaked_rows: Array = []
var scanned_strings := 0
var scanned_screens := 0
var unknown_fonts: Array = []
var _reported := false
## FONT_AUDIT_BASELINE=1 reproduces the pre-fix font assignment (a font with no
## fallback chain) over the very same screens, so the before/after rows come from
## one measuring instrument instead of two different builds.
var baseline_mode := OS.get_environment("FONT_AUDIT_BASELINE") == "1"

const FONT_THEME_ITEM := {
	"Label": "font",
	"Button": "font",
	"CheckBox": "font",
	"CheckButton": "font",
	"OptionButton": "font",
	"LinkButton": "font",
	"LineEdit": "font",
	"RichTextLabel": "normal_font",
	"TextEdit": "font",
}

func _ready() -> void:
	Demo.test_mode = true
	_watchdog()
	add_child(load("res://game/map/Main.tscn").instantiate())
	await wait(0.4)

	scan("title")
	Utils.gameStart()
	await wait(0.4)
	scan("hud-camp")

	# Half the labels on these screens have an "owned / activated" variant that
	# only exists once something has been bought. Grant everything so the audit
	# sees the real strings instead of only the empty-profile ones.
	grant_everything()
	await wait(0.3)

	# Camp configuration panel: every tab plus real entry presses (the entry
	# actions are bound to Button.pressed, so pressing them is the real path).
	# `Demo.ui` can be replaced by anything that reloads the main scene, so every
	# step re-opens it and re-reads it instead of trusting a captured reference.
	for tab in ["weapon", "attachment", "magazine", "talent", "stage"]:
		var panel = await open_panel()
		if panel == null: break
		panel.switch_tab(tab)
		await wait(0.3)
		scan("camp-" + tab)
		for i in 2:
			panel = await open_panel()
			if panel == null: break
			var entries: Array = panel.listing.get_children()
			if i >= entries.size(): break
			var entry = entries[i]
			if not is_instance_valid(entry) or not entry is Button: continue
			var key: String = entries[i].name
			entry.pressed.emit()
			await wait(0.25)
			scan("camp-" + tab + "-detail-" + str(i) + "-" + str(key))
		panel = await open_panel()
		if tab == "attachment" and panel != null and panel.has_method("show_reset"):
			panel.show_reset()
			await wait(0.25)
			scan("camp-reset-dialog")
			for child in panel.get_children():
				if child is ConfirmationDialog: child.queue_free()
			await wait(0.15)
	await close_panels()

	# A few weapons equipped in turn: the HUD weapon banner prints weapon_name,
	# and several of those values are literal translation keys. Three samples are
	# enough - the banner is one label, and the point is which *font* renders it.
	for id in ["0", "111", "124"]:
		if not is_instance_valid(Utils.player): break
		Utils.player.changeWeapon(int(id))
		await wait(0.15)
		scan("hud-weapon-" + str(id))

	# Character stat sheet.
	Demo.open_stats()
	await wait(0.4)
	scan("stats")
	await close_panels()

	# Pause / settings.
	Demo.open_settings()
	await wait(0.4)
	scan("settings")
	await close_panels()

	# Reward picker, scoreboard, death board, save dialog, mode select.
	for path in ["res://ui/widgets/RewardChoose.tscn", "res://ui/widgets/Scoreboard.tscn",
			"res://ui/widgets/DeathBoard.tscn", "res://ui/ModeSelect.tscn",
			"res://ui/widgets/WeaponChoose.tscn", "res://ui/widgets/Tooltip.tscn"]:
		if not ResourceLoader.exists(path):
			continue
		var ins = load(path).instantiate()
		Utils.canvasLayer.add_child(ins)
		await wait(0.35)
		scan(path.get_file())
		ins.queue_free()
		await wait(0.2)

	Demo.show_save_dialog(true)
	await wait(0.4)
	scan("save-dialog")
	for child in Utils.canvasLayer.get_children():
		var script = child.get_script()
		if script != null and str(script.resource_path).ends_with("SaveDialog.gd"):
			child.queue_free()
	await close_panels()

	# Title screen settings overlay (MainUI/SettingUI).
	var main_ui = Utils.canvasLayer.get_node_or_null("MainUI")
	if main_ui != null:
		main_ui.get_node("SettingUI").visible = true
		await wait(0.3)
		scan("title-settings")
		main_ui.get_node("SettingUI").visible = false

	# Toast + level-up notices use their own fonts.
	Utils.showToast("START_TIP", 5)
	await wait(0.3)
	scan("toast")

	_audit_static_scene_text()
	_report()

## Screens that are only reachable deep inside a run (reward picker variants,
## boss bars, death board bodies, snow world) still carry static text in their
## scene files. Those strings are checked against the project default theme font.
func _audit_static_scene_text() -> void:
	var default_font: Font = ThemeDB.get_project_theme().default_font
	if default_font == null:
		default_font = ThemeDB.get_default_theme().default_font
	var files := _all_scene_files("res://")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "": continue
		for line in text.split("\n"):
			var trimmed := line.strip_edges()
			if not trimmed.begins_with("text = \""): continue
			var value := trimmed.trim_prefix("text = \"").trim_suffix("\"")
			if value == "": continue
			scanned_strings += 1
			var miss: Array = []
			for i in value.length():
				var cp := value.unicode_at(i)
				if cp < 0x21: continue
				if not _covers(default_font, cp): miss.append("U+%04X" % cp)
			if not miss.is_empty():
				missing_rows.append({
					"screen": "static:" + path,
					"node": "(scene property)",
					"class": "SceneFile",
					"field": "text",
					"text": value,
					"missing": miss,
					"pua": false,
					"fonts": _chain_paths(default_font),
				})

func _all_scene_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null: return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if name not in [".godot", "build", "docs", "tests", "tools", "addons", "evidence", "archive"]:
				out.append_array(_all_scene_files(dir.path_join(name)))
		elif name.ends_with(".tscn") or name.ends_with(".tres"):
			out.append(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out

## A scripted screen walk can die on a single bad call (a coroutine that throws
## simply stops). Without this the process would sit there forever and a hung
## audit would look like a slow one.
func _watchdog() -> void:
	var timer := Timer.new()
	timer.wait_time = 900.0
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(func():
		print("FONT_AUDIT_TIMEOUT")
		_report())
	add_child(timer)
	timer.start()

func close_panels() -> void:
	for menu in Demo.pause_stack.duplicate():
		Demo.pop_pause(menu)
		menu.queue_free()
	await wait(0.2)

## Re-opens the camp panel and returns it, or null when the main scene went away.
func open_panel():
	if not is_instance_valid(Demo.ui):
		Demo.ui = null
		Demo.open_panel()
		await wait(0.25)
	return Demo.ui if is_instance_valid(Demo.ui) and Demo.ui.has_method("switch_tab") else null

func grant_everything() -> void:
	LevelServer.state = "CAMP"
	PlayerData.gold = 999999
	PlayerData.reward_point = 9999
	for id in Utils.am_dict:
		Demo.try_purchase("attachment", id)
	for id in Utils.weapon_list:
		Demo.try_purchase("weapon", id)
	for id in DemoConfig.TALENTS:
		var guard := 0
		while Demo.rank(id) < DemoConfig.TALENTS[id].max and guard < 12:
			Demo.try_purchase("talent", id, "points")
			guard += 1
	for id in RewardServer.reward_list:
		Demo.try_purchase("legacy", id)
	# Show the reward picker with everything already owned, so its "已拥有"
	# variants are audited too.
	var rewards = load("res://ui/widgets/RewardChoose.tscn").instantiate()
	Utils.canvasLayer.add_child(rewards)
	await wait(0.35)
	scan("reward-choose-owned")
	rewards.queue_free()
	await wait(0.2)

## Frame-based rather than wall-clock waiting: the audit only needs the UI to
## have run its deferred renders, and a headless run has no vsync to pace it.
func wait(seconds: float) -> void:
	for i in maxi(2, int(seconds * 30.0)):
		await get_tree().process_frame

func scan(screen: String) -> void:
	scanned_screens += 1
	_walk(get_tree().root, screen)

func _walk(node: Node, screen: String) -> void:
	if node is Control or node is Window:
		_consider(node, screen)
	for child in node.get_children():
		_walk(child, screen)

func _theme_item_for(node: Node) -> String:
	for key in FONT_THEME_ITEM:
		if node.is_class(key):
			return FONT_THEME_ITEM[key]
	return ""

func _consider(node: Node, screen: String) -> void:
	var item := _theme_item_for(node)
	if item == "": return
	var font: Font = null
	if node is Label and node.get("label_settings") != null and node.label_settings.font != null:
		font = node.label_settings.font
	else:
		font = node.get_theme_font(item)
	var texts: Array = []
	if node.get("text") != null:
		texts.append([str(node.text), "text"])
	if node is OptionButton:
		for i in node.item_count:
			texts.append([node.get_item_text(i), "item%d" % i])
	if node is RichTextLabel:
		texts.append([node.get_parsed_text(), "parsed"])
	for entry in texts:
		_check(screen, node, font, entry[0], entry[1])

func _check(screen: String, node: Node, font: Font, text: String, field: String) -> void:
	if text.strip_edges() == "": return
	scanned_strings += 1
	if font == null:
		unknown_fonts.append("%s %s" % [screen, node.get_path()])
		return
	var miss: Array = []
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp < 0x21: continue
		if not _covers(font, cp):
			miss.append(cp)
	if not miss.is_empty():
		var uniq := {}
		for cp in miss: uniq[cp] = true
		missing_rows.append({
			"screen": screen,
			"node": str(node.get_path()),
			"class": node.get_class(),
			"field": field,
			"text": text,
			"missing": uniq.keys().map(func(c): return "U+%04X" % c),
			"pua": uniq.keys().any(func(c): return c >= 0xE000 and c <= 0xF8FF),
			"fonts": _chain_paths(font),
		})
	var stripped := text.strip_edges()
	if stripped.length() >= 4 and stripped == stripped.to_upper() \
			and stripped.replace("_", "").is_valid_identifier() and "_" in stripped \
			and TranslationServer.translate(stripped) == stripped:
		leaked_rows.append({"screen": screen, "node": str(node.get_path()), "text": stripped})

## Coverage is resolved once per font resource (a full set lookup) rather than
## per character: Font.has_char() is far too slow to call tens of thousands of
## times, which is what made the first version of this audit take minutes.
var _coverage_cache: Dictionary = {}

func _coverage(font: Font, depth := 0) -> Dictionary:
	if font == null or depth > 4: return {}
	var key := font.get_instance_id()
	if _coverage_cache.has(key): return _coverage_cache[key]
	var set := {}
	# Keyed by codepoint (int) to match the lookup in _covers().
	for ch in font.get_supported_chars():
		set[ch.unicode_at(0)] = true
	if font is FontVariation and font.base_font != null:
		for ch in _coverage(font.base_font, depth + 1):
			set[ch] = true
	if not baseline_mode:
		for fb in font.fallbacks:
			for ch in _coverage(fb, depth + 1):
				set[ch] = true
	_coverage_cache[key] = set
	return set

func _covers(font: Font, cp: int) -> bool:
	return _coverage(font).has(cp)

func _chain_paths(font: Font, depth := 0) -> Array:
	if font == null or depth > 4: return []
	var out: Array = []
	var label := font.resource_path
	if label == "": label = font.get_class()
	if font is FontVariation and font.base_font != null:
		label += " (base)"
		out.append(label)
		out.append_array(_chain_paths(font.base_font, depth + 1))
	else:
		out.append(label)
	for fb in font.fallbacks:
		out.append_array(_chain_paths(fb, depth + 1))
	return out

func _report() -> void:
	if _reported: return
	_reported = true
	print("FONT_AUDIT_SCREENS ", scanned_screens)
	print("FONT_AUDIT_STRINGS ", scanned_strings)
	print("FONT_AUDIT_MISSING ", missing_rows.size())
	print("FONT_AUDIT_LEAKED ", leaked_rows.size())
	print("FONT_AUDIT_NOFONT ", unknown_fonts.size())
	for row in missing_rows:
		print("FONT_AUDIT_ROW ", JSON.stringify(row))
	for row in leaked_rows:
		print("FONT_AUDIT_LEAK ", JSON.stringify(row))
	print("FONT_AUDIT_RESULT ", "PASS" if missing_rows.is_empty() else "FAIL")
	get_tree().quit(0 if missing_rows.is_empty() else 1)

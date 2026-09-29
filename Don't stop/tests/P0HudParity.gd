extends "res://tests/M8Runtime.gd"

## P0 product/HUD parity.
##
## The manual acceptance report was "HP 始终 100%", which three different defects
## produce identically:
##   A  real HP drops and the bar drops  -> the product path is healthy
##   B  real HP drops, the bar stays     -> a HUD defect
##   C  real HP never drops              -> a damage-path defect
##
## This fixture separates them. It runs a REAL session: no `Demo.test_mode`, no
## `--e2e`, no smoke invincibility, a real camp departure and real monsters. The
## player never presses an input, exactly like the manual run, and every frame
## the LIVE `GameUI` bar is compared against `PlayerData`.
const FIXTURE_SAVE := "user://p0-hud-parity-camp.json"
const OBSERVE_SECONDS := 55.0

func _ready():
	# A product launch reads the real save. Redirect it so this fixture can never
	# read or overwrite the player's own camp, and start from an empty one.
	Demo.save_path = FIXTURE_SAVE
	if FileAccess.file_exists(FIXTURE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_SAVE))
	Demo.test_mode = false
	seed(808)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.6)
	dismiss()
	check(not Demo.test_mode and not Demo.is_e2e_mode(),"the product session runs without test mode or E2E immunity")
	check(LevelServer.state == "CAMP","a real product launch reaches the camp")
	check(PlayerData.player_hp == 5.0 and PlayerData.player_hp_max == 5.0,"a fresh product save starts at the authored 5 HP")

	var ui = Utils.canvasLayer.get_node_or_null("GameUI")
	check(ui != null,"the product HUD exists")
	if ui == null:
		get_tree().quit(1)
		return
	var bar: ProgressBar = ui.get_node_or_null("hpUI/ProgressBar")
	check(bar != null,"the product HP bar exists")
	if bar == null:
		get_tree().quit(1)
		return
	# The reported bug is the bar showing a value PlayerData does not have. Measure
	# it on construction, before any combat.
	check(is_equal_approx(bar.max_value,PlayerData.player_hp_max),"the HP bar max mirrors PlayerData.player_hp_max at construction")
	check(is_equal_approx(bar.value,PlayerData.player_hp),"the HP bar value mirrors PlayerData.player_hp at construction")
	print("P0_HUD bar path=%s show_percentage=%s size=%s visible=%s" % [bar.get_path(),str(bar.show_percentage),str(bar.size),str(bar.is_visible_in_tree())])

	# Arm the player through the same legal purchase the camp uses, so the round is
	# the ordinary armed campaign departure rather than the unarmed edge case.
	if Demo.try_purchase("weapon","112").success:
		Utils.player.changeWeapon(112)
		print("P0_HUD armed weapon=112")
	else:
		print("P0_HUD armed=none (unarmed is a legal first-class state)")

	var departed: bool = LevelServer.town.depart(Demo.next_stage,false)
	check(departed,"the campaign door departs into a real round")
	var deadline := Time.get_ticks_msec()+8000
	while LevelServer.state != "COMBAT" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(LevelServer.state == "COMBAT","the round really starts in COMBAT")
	# The spawn director adds the first wave a moment after the round opens.
	deadline = Time.get_ticks_msec()+10000
	while get_tree().get_nodes_in_group("monsters").is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not get_tree().get_nodes_in_group("monsters").is_empty(),"the round really contains monsters")

	# From here nothing presses an input. Real monsters have to reach and hit a
	# player who never moves.
	var hp_start: float = PlayerData.player_hp
	var min_hp := hp_start
	var first_hit_hp := hp_start
	var first_hit_bar := hp_start
	var parity_failures := 0
	var desync_samples := 0
	var clock := 0.0
	while clock < OBSERVE_SECONDS and not Utils.player.is_dead and LevelServer.state == "COMBAT":
		await get_tree().process_frame
		clock += get_process_delta_time()
		var hp: float = PlayerData.player_hp
		if hp < min_hp:
			if min_hp == hp_start:
				first_hit_hp = hp
				first_hit_bar = bar.value
			min_hp = hp
		# A Range snaps its value to its own `step`, so the bar is allowed to differ
		# from PlayerData by at most one step - never by a visible amount.
		if not is_equal_approx(bar.max_value,PlayerData.player_hp_max) or absf(bar.value-hp) > maxf(bar.step,0.0001):
			parity_failures += 1
			if desync_samples < 4:
				desync_samples += 1
				print("P0_HUD DESYNC hp=%.6f bar=%.6f hp_max=%.4f bar_max=%.4f step=%.4f" % [hp,bar.value,PlayerData.player_hp_max,bar.max_value,bar.step])

	var summary := {"hp_start":hp_start,"hp_min":min_hp,"hp_end":PlayerData.player_hp,
		"bar_end":bar.value,"bar_max":bar.max_value,"hp_max":PlayerData.player_hp_max,
		"dead":Utils.player.is_dead,"state":LevelServer.state,"observed_s":clock,
		"parity_failures":parity_failures,"first_hit_hp":first_hit_hp,"first_hit_bar":first_hit_bar}
	print("P0_HUD_PARITY ",JSON.stringify(summary))

	check(min_hp < hp_start,"real monsters lower real PlayerData.player_hp while the player does nothing")
	check(first_hit_bar < hp_start,"the HP bar dropped with the first real hit")
	check(parity_failures == 0,"the HP bar mirrored PlayerData on every observed frame")

	print("P0_HUD_PARITY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

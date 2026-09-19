extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	configure(0,false)
	var gun = Utils.player.gun
	gun.is_use = true
	seed(20260919)
	var expected = []
	for i in 9: expected.append(randi())
	seed(20260919)
	gun._shootAnim()
	var observed = []
	for i in 6: observed.append(randi())
	check(gun.tier_muzzle.remaining>0,"full production shoot animation actually ran")
	var legacy_draws = 2 if DisplayServer.get_name() == "headless" else 3
	check(observed == expected.slice(legacy_draws,legacy_draws+6),"full shoot animation preserves the baseline engine RNG sequence")
	print("PRESENTATION_RNG ",JSON.stringify({"sequence":expected,"observed":observed,"legacy_draws":legacy_draws,"matches_legacy":observed==expected.slice(legacy_draws,legacy_draws+6)}))
	if DisplayServer.get_name() != "headless":
		await wait(0.4)
		seed(20260919)
		RenderingServer.force_draw(false)
		var control_draw = []
		for i in 6: control_draw.append(randi())
		seed(20260919)
		gun._shootAnim()
		RenderingServer.force_draw(false)
		var animation_draw = []
		for i in 6: animation_draw.append(randi())
		check(animation_draw == expected.slice(legacy_draws,legacy_draws+6),"rendered animation also preserves the baseline RNG sequence")
		print("PRESENTATION_RNG_DRAW ",JSON.stringify({"control":control_draw,"animation":animation_draw,"matches_legacy":animation_draw==expected.slice(legacy_draws,legacy_draws+6)}))
	Demo.open_panel()
	await wait(0.1)
	for quality in [0,1,2,3,4,5]:
		Demo.ui.tier_filter = quality
		seed(20260919)
		var camp_sequence: Array = []
		for i in 16: camp_sequence.append(randi())
		seed(20260919)
		Demo.ui.render()
		var camp_observed: Array = []
		for i in 6: camp_observed.append(randi())
		# Measure the original display-scene lifecycle on this actual backend.
		seed(20260919)
		if quality == 0 or quality == WeaponCatalog.tier(6):
			var legacy_model = Utils.weapon_list["6"].instantiate()
			legacy_model.free()
		var expected_draws = camp_sequence.find(randi())
		check(camp_observed == camp_sequence.slice(expected_draws,expected_draws+6),"cached Camp preserves the baseline RNG sequence for quality "+str(quality))
		print("PRESENTATION_CAMP_RNG ",JSON.stringify({"quality":quality,"draws":camp_sequence.find(camp_observed[0]),"expected_draws":expected_draws,"observed":camp_observed}))
	dismiss()
	# Compare both builds' real call sequence; a baseline visual may already consume RNG.
	print("PRESENTATION_RNG checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

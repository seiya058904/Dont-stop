extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	# The result card is information-dense by design: keep its live layout close
	# to the authored 174x116 design rectangle instead of regressing to a modal
	# that consumes most of the viewport.
	var result_card = load("res://ui/widgets/Scoreboard.tscn").instantiate()
	result_card.setData({"time":125,"kill":18,"gold":42,"stage":1,"trial":false})
	add_child(result_card)
	await get_tree().process_frame
	check(result_card.get_node("Panel").size.x >= 160 and result_card.get_node("Panel").size.x <= 180,"result card keeps a compact width")
	check(result_card.get_node("Panel").size.y >= 105 and result_card.get_node("Panel").size.y <= 120,"result card keeps a compact height")
	check(result_card.get_node("Panel/Button").size.y <= 18,"result card confirmation stays concise")
	result_card.queue_free()
	await get_tree().process_frame
	configure(124,false)
	var ui = Utils.canvasLayer.get_node("GameUI")
	for sample in [[100,40.0],[60,24.0],[1,0.4],[0,0.0]]:
		var amount: int = sample[0]
		Utils.player.gun.bullets_count = amount
		ui.onWeaponBulletsChange(amount,100)
		ui._update_weapon_readout()
		check(ui.ammo_count_label.text == "%d/100" % amount,"real magazine readout "+str(amount))
		check(is_equal_approx(ui.ammo_lit,sample[1]),"100-round magazine graphic "+str(amount))
		check(ui.current_weapon_icon.texture == Utils.player.gun.image,"HUD and hand share the same texture")
	Utils.player.gun.reload_ammo()
	ui._update_weapon_readout()
	check(ui.current_weapon_label.text.begins_with("装填"),"reload readout follows real gun state")
	Utils.player.gun.cancel_actions()
	LevelServer.state = "CAMP"
	Demo.unequip_weapon()
	ui._update_weapon_readout()
	check(ui.current_weapon_label.text == "未装备武器" and ui.current_weapon_icon.texture == null,"unarmed HUD clears icon and names the state")
	var hit_label = load("res://ui/widgets/HitLabel.gd").new()
	for pair in [[0.875,"0.88"],[1.0,"1"],[150.0,"150"],[0.001,"<0.01"],[12.5,"12.5"]]:
		hit_label.setNumber(pair[0])
		check(hit_label.text == pair[1],"damage display precision "+str(pair[0]))
	hit_label.setNumber("护盾")
	check(hit_label.text == "护盾","status feedback is not converted to numeric zero")
	hit_label.free()
	var muzzle = load("res://game/effects/TierMuzzle.gd").new()
	add_child(muzzle)
	seed(701)
	var expected = randf()
	seed(701)
	for key in Utils.weapon_list:
		muzzle.pulse(WeaponCatalog.tier(int(key)),int(key))
		check(muzzle.remaining <= 0.09 and muzzle.get_child_count() == 0,"bounded reusable muzzle "+str(key))
	check(randf() == expected,"muzzle decoration consumes no gameplay RNG")
	muzzle.stop()
	check(not muzzle.visible and not muzzle.is_processing(),"muzzle fully stops on interruption")
	muzzle.queue_free()
	configure(116,false)
	LevelServer.state = "COMBAT"
	var thermal = Utils.player.gun
	thermal.direction = Vector2.RIGHT
	thermal.handle_thermal(true,0.1)
	var visual = thermal.thermal_visual
	var remaining_ammo = thermal.bullets_count
	thermal.handle_thermal(true,0.1)
	check(is_instance_valid(visual) and visual == thermal.thermal_visual,"thermal ticks reuse one actual-footprint visual")
	check(thermal.bullets_count == remaining_ammo-1,"visual reuse preserves the real 0.1-second ammunition tick")
	thermal.handle_thermal(false,0.01)
	check(thermal.thermal_visual == null,"thermal release ends its visual immediately")
	await wait(0.3)
	var effect_script = load("res://game/effects/CombatEffect.gd")
	var effects: Array = []
	for index in 70:
		var effect = effect_script.new()
		effect.points.assign([Vector2.ZERO,Vector2(10,0)])
		add_child(effect)
		effects.append(effect)
	check(effect_script.detail_slots <= 64,"optional player burst slots remain bounded")
	check(effects.size() == 70 and effects.all(func(effect): return effect.points.size() == 2),"budget never discards resolved paths")
	for effect in effects: effect.queue_free()
	await wait(0.05)
	check(effect_script.detail_slots == 0,"optional slots return to zero after cleanup")
	var contact_script = preload("res://game/effects/ImpactAccent.gd")
	seed(9028)
	var contact_rng = randi()
	seed(9028)
	for index in 40:
		var target := Node2D.new()
		add_child(target)
		Combat._contact_accent(target,index%2 == 0,{})
		Combat._contact_accent(target,false,{})
		target.free()
	check(contact_script.active == contact_script.LIMIT,"crowded hits respect contact cap and per-target coalescing")
	check(randi() == contact_rng,"resolved contact decoration does not consume gameplay RNG")
	await wait(0.35)
	check(contact_script.active == 0,"contact budget returns after its short lifetime")
	print("PRESENTATION_CONTRACTS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

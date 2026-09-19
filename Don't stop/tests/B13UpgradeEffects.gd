extends "res://tests/M8Runtime.gd"
## B13 upgrade effect contract. For EVERY one of the 24 upgrades, buying it must really
## change exactly what its catalog entry declares - computed from the live definition, not
## from card text - on an ordinary bullet gun (0) and on the beam gun (6), so "all current
## and future weapons" stays a runtime fact, not a slogan.

var gun_a: BaseGun
var gun_b: BaseGun
var base_a: Dictionary
var base_b: Dictionary

func ranks_clear():
	Demo.owned_global_upgrades.clear()
	Demo.talents.clear()
	Demo.refresh()

func expected_from(def: Dictionary, key: String, baseline: float) -> float:
	match key:
		"damage": return baseline*(1.0+float(def.get("damage",0.0)))*float(def.get("damage_mul",1.0))
		"magazine": return float(maxi(1,int(baseline*float(def.get("magazine_mul",1.0)))))
		"reload": return maxf(DemoConfig.MIN_RELOAD_SECONDS,baseline*float(def.get("reload_mul",1.0)))
		"crit": return clampf(baseline+float(def.get("crit",0.0)),0.0,1.0)
		"range","width","angle","turn","lock_angle","warmup","recovery":
			var mul_key = key+"_mul"
			return baseline*float(def.get(mul_key,1.0))
		"spread": return baseline*float(def.get("spread_mul",1.0))
		"impulse": return baseline*float(def.get("impulse_mul",1.0))
		"radius": return baseline*float(def.get("radius_mul",1.0))
		"jumps": return baseline+float(def.get("jumps",0))
		"pierce","bounces","shards","refill": return baseline+float(def.get(key,0))
		"bounce_retention","shard_ratio": return float(def.get(key,baseline))
	return baseline

func verify_gun(gun: BaseGun, baseline: Dictionary, id: int, label: String):
	var d: Dictionary = AttachmentCatalog.DEFINITIONS[id]
	var eff: Dictionary = gun.effective
	var any_delta := false
	for key in ["damage","magazine","reload","crit","range","spread","impulse","radius","jumps","pierce","bounces","shards","refill","width","angle","turn","lock_angle","warmup","recovery"]:
		var expected := expected_from(d,key,float(baseline.get(key,0.0)))
		var actual := float(eff.get(key,0.0))
		if not is_equal_approx(expected,actual):
			check(false,"%s %s: expected %.4f got %.4f"%[label,key,expected,actual])
			return
		if not is_equal_approx(expected,float(baseline.get(key,0.0))): any_delta = true
	check(any_delta,label+" really changes the build")

func _ready():
	await boot()
	configure(0,false)
	gun_a = Utils.player.gun
	configure(6,false)
	gun_b = Utils.player.gun
	#--- baseline with an empty account ------------------------------------------------
	Utils.player.changeWeapon(0)
	ranks_clear()
	base_a = gun_a.effective.duplicate(true)
	check(is_equal_approx(base_a.damage,(gun_a.base_stats.damage+PlayerData.player_damage)*WeaponCatalog.power(0)),
		"baseline damage is the unupgraded build (got %.4f, expected %.4f)"%[base_a.damage,(gun_a.base_stats.damage+PlayerData.player_damage)*WeaponCatalog.power(0)])
	Utils.player.changeWeapon(6)
	base_b = gun_b.effective.duplicate(true)
	Utils.player.changeWeapon(0)
	Utils.player.changeWeapon(0)
	for id_key in Utils.am_dict:
		var id := int(id_key)
		ranks_clear()
		check(Demo.try_purchase("attachment",id_key).success,"purchase "+id_key)
		verify_gun(gun_a,base_a,id,"upgrade %s on gun 0"%id_key)
		Utils.player.changeWeapon(6)
		verify_gun(gun_b,base_b,id,"upgrade %s on gun 6"%id_key)
		Utils.player.changeWeapon(0)
	#--- targeted mechanism secondaries on the guns that support them --------------------
	for wid in [113,117,120]: Demo.try_purchase("weapon",str(wid))
	ranks_clear()
	Demo.try_purchase("attachment","115")
	Utils.player.changeWeapon(113)
	var rail = Utils.player.gun
	check(rail.weapon_id == 113 and is_equal_approx(float(rail.effective.warmup),0.8*0.9),"115 warmup secondary is real on the B14 0.8s charged rail")
	ranks_clear()
	Demo.try_purchase("attachment","119")
	Utils.player.changeWeapon(117)
	var ricochet = Utils.player.gun
	check(ricochet.weapon_id == 117 and int(ricochet.effective.bounces)==3,"119 bounce secondary adds the ricochet bounce")
	ranks_clear()
	Demo.try_purchase("attachment","123")
	Utils.player.changeWeapon(120)
	var missile = Utils.player.gun
	check(missile.weapon_id == 120 and is_equal_approx(float(missile.effective.turn),2.2*1.3) and is_equal_approx(float(missile.effective.lock_angle),0.65*1.2),"123 homing secondary is real on the missile rack")
	#--- grenade unlock is a real all-weapon mechanism ------------------------------------
	ranks_clear()
	LevelServer.state = "COMBAT"
	Utils.player.global_position = origin
	check(not Demo.fire_global_grenade(origin+Vector2(60,0)),"grenade locked without upgrade 9")
	LevelServer.state = "CAMP"
	check(Demo.try_purchase("attachment","9").success,"upgrade 9 purchases in camp")
	LevelServer.state = "COMBAT"
	Demo.grenade_cooldown = 0
	check(Demo.fire_global_grenade(origin+Vector2(60,0)),"upgrade 9 unlocks the right-click grenade")
	check(Demo.grenade_cooldown > 0,"grenade entered its cooldown")
	for node in get_tree().root.get_children():
		if node.get_script() and node.get_script().resource_path == "res://game/other/Grenade.gd": node.queue_free()
	LevelServer.return_to_camp()
	#--- stacking bounds with everything owned --------------------------------------------
	ranks_clear()
	for id_key in Utils.am_dict: Demo.try_purchase("attachment",id_key)
	for id in DemoConfig.TALENTS:
		while Demo.rank(id) < DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	gun_a.updateGun()
	check(float(gun_a.effective.crit) <= 1.0,"crit stays capped with the full account")
	check(float(gun_a.effective.reload) >= DemoConfig.MIN_RELOAD_SECONDS,"reload stays above the floor with the full account")
	check(float(gun_a.effective.rate) <= 60.0,"rate stays under the non-rotary cap")
	check(int(gun_a.effective.magazine) >= 1,"magazine stays a positive integer")
	check(Combat.max_depth_seen <= 2,"derivation depth never exceeded the B11 bound")
	print("B13_UPGRADE_EFFECTS_CHECKS ",checks," FAILURES ",failures," max_depth=",Combat.max_depth_seen)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

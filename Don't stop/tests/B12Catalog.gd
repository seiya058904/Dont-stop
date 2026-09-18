extends "res://tests/M8Runtime.gd"
## B12 catalog contract. The rework changed TIERS / PRICES / POWER values and moved every
## player-visible surface from "Tier N" to quality names, but the catalog's shape must hold:
## exactly 24 stable IDs, every tier in 1..5, every player-facing quality name derived from
## the same tier, prices strictly banded by quality (non-overlapping), and the shop list
## must keep using the catalog price as its single source of truth.

func _ready():
	await boot()
	var ids: Array = []
	for key in Utils.weapon_list: ids.append(int(key))
	check(ids.size()==24,"exactly 24 weapons in the runtime list")
	check(ids.size()==WeaponCatalog.TIERS.size(),"every weapon has a tier entry")
	var seen := {}
	var dup := false
	for id in ids:
		if seen.has(id): dup = true
		seen[id] = true
	check(not dup,"no duplicate weapon IDs")
	for id in ids:
		var t: int = WeaponCatalog.tier(id)
		check(t>=1 and t<=5,"tier inside 1..5 for "+str(id))
		check(WeaponCatalog.rarity(id)==WeaponCatalog.RARITY_NAMES[t-1],"rarity name mirrors tier for "+str(id))
		var price: int = int(WeaponCatalog.PRICES[str(id)])
		check(price>0,"positive price for "+str(id))
		check(int(Utils.weapon_money_list[str(id)])==price,"shop uses catalog price for "+str(id))
		check(WeaponCatalog.POWER.has(id),"POWER entry exists for "+str(id))
		check(float(WeaponCatalog.power(id))>0.0,"positive POWER for "+str(id))
	# Quality price bands: 普通 < 精良 < 稀有 < 史诗 < 传说, band-overlap forbidden.
	for t in range(1,5):
		var lows: Array = []
		var highs: Array = []
		for id in ids:
			if WeaponCatalog.tier(id)==t: lows.append(int(WeaponCatalog.PRICES[str(id)]))
			if WeaponCatalog.tier(id)==t+1: highs.append(int(WeaponCatalog.PRICES[str(id)]))
		check(lows.size()>0 and highs.size()>0,"both quality bands populated for %d/%d"%[t,t+1])
		check(int(maxv(lows))<int(minv(highs)),"quality %d price band strictly below quality %d"%[t,t+1])
	# Every new-quality definition still carries name + info so shop cards keep their text.
	for id in ids:
		var gun = Utils.weapon_list[str(id)].instantiate()
		check(tr(gun.weapon_name)!="","weapon name present for "+str(id))
		gun.free()
	# --- aim_override production guard ------------------------------------------------
	# The test-only aim hook must be inert outside Demo.test_mode, even if a stray
	# assignment happens: gameplay aim must keep reading the real viewport mouse.
	var saved_override: Variant = Utils.aim_override
	var saved_test_mode: bool = Demo.test_mode
	Utils.aim_override = Vector2(7777,7777)
	Demo.test_mode = true
	check(Utils.get_aim_viewport_position()==Vector2(7777,7777),"aim hook is honoured in test mode")
	Demo.test_mode = false
	check(Utils.get_aim_viewport_position()==Utils.get_viewport().get_mouse_position(),
		"aim hook is inert outside test mode and reads the real viewport mouse")
	check(Utils.get_aim_viewport_position()!=Vector2(7777,7777),"a stray aim_override cannot move production aim")
	Demo.test_mode = saved_test_mode
	Utils.aim_override = saved_override
	print("B12_CATALOG_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

func maxv(values: Array) -> float:
	var m: float = -INF
	for v in values: m = maxf(m,float(v))
	return m
func minv(values: Array) -> float:
	var m: float = INF
	for v in values: m = minf(m,float(v))
	return m

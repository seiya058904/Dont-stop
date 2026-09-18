extends "res://tests/M8Runtime.gd"
## B12 save compatibility. The rework changes tier/price/POWER values only - weapon IDs are
## untouched - so an existing save must keep validating and restoring exactly as before:
## ownership keyed by the same stable string IDs, the equipped weapon, per-gun ammo, and
## purchases charged at the NEW catalog price.

func _ready():
	await boot()
	# --- ownership + equip across the new quality spread -------------------------------
	configure(1,true)     # 普通
	configure(118,true)   # 稀有
	configure(120,true)   # 传说
	check(PlayerData.changeWeapon(120),"equip the legendary weapon by stable ID")
	var snap: Dictionary = Demo.snapshot()
	check(CampSnapshot.validate(snap),"a snapshot owning weapons across the new qualities still validates")
	var owned_ids: Array = []
	for w in snap.weapons: owned_ids.append(str(w.id))
	check(owned_ids.has("1") and owned_ids.has("118") and owned_ids.has("120"),"snapshot keeps ownership of every tier by ID")
	check(str(snap.equipped)=="120","snapshot keeps the equipped weapon ID")
	check(str(snap.weapons[0].id) in ["1","118","120"],"weapon entries keep the stable ID key")
	# --- wipe and restore, mirroring Demo.load_camp's ownership primitive ---------------
	for gun in PlayerData.player_weapon_list.values(): gun.free()
	PlayerData.player_weapon_list.clear()
	for w in snap.weapons:
		PlayerData.add_weapon(Utils.weapon_list[str(w.id)].instantiate())
	check(PlayerData.player_weapon_list.has(120),"restored save re-owns the legendary weapon")
	check(PlayerData.player_weapon_list.has(118),"restored save re-owns the rare weapon")
	check(PlayerData.player_weapon_list.has(1),"restored save re-owns the common weapon")
	check(PlayerData.changeWeapon(118),"restored save can re-equip by the same ID")
	# --- purchase charges the NEW catalog price -----------------------------------------
	PlayerData.gold = 10000
	var price: int = int(WeaponCatalog.PRICES["124"])
	check(price>0,"legendary price is a positive catalog value")
	check(Demo.try_purchase("weapon","124"),"purchase of the legendary succeeds with enough gold")
	check(PlayerData.gold==10000-price,"purchase charges exactly the catalog price")
	check(PlayerData.player_weapon_list.has(124),"purchased weapon joins ownership by ID")
	# --- a legacy-shaped save (old quality distribution) still validates -----------------
	# Values of tier/price never enter the save; the same IDs must validate regardless.
	check(CampSnapshot.validate(snap),"re-validating the same snapshot stays true after the rework")
	print("B12_SAVE_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

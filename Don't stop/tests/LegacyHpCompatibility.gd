extends "res://tests/M8Runtime.gd"

# HistoricalHelmet is the unchanged reward script from 3946250809ea369d1dfc856e87476100a6d14f69.
# That version's normal camp purchases cost 100 gold / 1 point, with 9999 of each
# initially available, cap 99, and no XP award. Run its actual growth callbacks.
const HISTORICAL_HELMET = preload("res://tests/fixtures/HistoricalHelmet.gd")

func _ready():
	await boot(); configure(0)
	Demo.save_path = "user://legacy-hp-compatibility-isolated.json"
	for layers in [40,41,99]:
		PlayerData.player_level = 1
		PlayerData.player_hp_max = 5
		var helmet = HISTORICAL_HELMET.new()
		helmet.onRewardStart()
		for rank in range(2,layers+1): helmet.count = rank
		helmet.free()
		var expected = 5.0+layers*3.0
		check(PlayerData.player_hp_max == expected,"historical normal growth produces "+str(expected))
		var data = Demo.snapshot()
		data.level=1; data.exp=0; data.legacy=[]; data.legacy_state={}; data.hp_max=expected; data.hp=expected
		for rank in layers: data.legacy.append("2")
		check(CampSnapshot.validate(data),"historical helmet input validates "+str(layers))
		var normalized = CampSnapshot.normalize(data)
		check(normalized.hp_max==expected and normalized.hp==expected,"normalization preserves "+str(expected))
		check(Demo.save_store.save(Demo.save_path,data).success and Demo.load_camp(),"load original historical file "+str(layers))
		check(PlayerData.player_hp_max==expected and PlayerData.player_hp==expected,"load preserves historical HP "+str(layers))
		Demo.test_mode = false
		Demo._start()
		Demo.test_mode = true
		check(Demo.load_camp(),"actual startup load/save then reload "+str(layers))
		check(PlayerData.player_hp_max==expected and PlayerData.player_hp==expected,"round trip preserves historical HP "+str(layers))
		check(Demo.purchases.count("2")==layers and not Demo.try_purchase("legacy","2","gold").success,"historical ownership kept, new cap unchanged "+str(layers))
		data.hp_max=100001; data.hp=100001
		var repaired = CampSnapshot.normalize(data)
		check(repaired.hp_max<1000 and repaired.hp<=repaired.hp_max,"historical ownership does not admit diagnostic pool "+str(layers))
	# Historical bacteria also granted 0.1 for each of 1000 kills; the persisted
	# kill count remains supported even though new growth stops at 100.
	var mixed = Demo.snapshot()
	mixed.level=1; mixed.exp=0; mixed.legacy.append("10"); mixed.legacy_state={"10":1000}
	mixed.hp_max=5+99*3+100+3; mixed.hp=mixed.hp_max
	check(CampSnapshot.validate(mixed),"combined historical helmet/bacteria snapshot validates")
	check(CampSnapshot.normalize(mixed).hp_max==mixed.hp_max,"all historical HP sources remain admitted")
	check(Demo.save_store.save(Demo.save_path,mixed).success and Demo.load_camp() and Demo.save_camp().success and Demo.load_camp(),"combined history round trips through disk")
	check(PlayerData.player_hp_max==mixed.hp_max,"combined history remains intact after snapshot")
	print("LEGACY_HP_COMPATIBILITY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

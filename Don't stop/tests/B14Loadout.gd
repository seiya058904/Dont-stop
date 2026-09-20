extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	Demo.save_path = "user://b14-loadout-isolated.json"
	check(Demo.save_store.save(Demo.save_path,Demo.snapshot()).success and Demo.load_camp(),"fresh empty save reloads")
	check(not Demo.explicitly_unequipped,"fresh empty save retains first-purchase auto-equip intent")
	for id in [0,1,2,3,4,5,6,7,124]:
		check(Demo.try_purchase("weapon",str(id)).success,"purchase %d" % id)
	var slots = PlayerData.get("weapon_slots")
	check(slots is Array and slots.size() == 7,"independent fixed seven-slot loadout exists")
	if not slots is Array:
		complete(); return
	check(not slots.has(7) and not slots.has(124),"full loadout does not silently replace on purchase")
	var gold = PlayerData.gold
	var ammo = {}
	for id in PlayerData.player_weapon_list: ammo[id] = PlayerData.player_weapon_list[id].bullets_count
	check(PlayerData.call("remove_slot",1).success,"remove non-current slot")
	check(PlayerData.weapon_slots[1] == -1,"removed slot remains empty")
	PlayerData.switch_deadline = 0
	check(PlayerData.call("equip_owned",124,1).success,"explicitly replace with weapon 124")
	check(Utils.player.gun.weapon_id == 124,"new weapon actually becomes current")
	check(PlayerData.call("clear_loadout").success,"clear all seven slots")
	check(PlayerData.call("clear_loadout").success,"clear all is idempotent")
	check(Utils.player.gun == null and PlayerData.weapon_slots.count(-1) == 7,"clear truly disarms and empties")
	check(PlayerData.gold == gold and PlayerData.player_weapon_list.size() == 9,"ownership and wallet preserved")
	for id in ammo: check(PlayerData.player_weapon_list[id].bullets_count == ammo[id],"ammo preserved %d" % id)
	var snapshot = Demo.snapshot()
	check(snapshot.has("weapon_slots") and snapshot.weapon_slots.count(-1) == 7,"explicit empty loadout serialized")
	check(Demo.save_store.save(Demo.save_path,snapshot).success,"isolated save writes")
	check(Demo.load_camp(),"isolated save reloads")
	check(PlayerData.weapon_slots.count(-1) == 7 and Utils.player.gun == null,"empty survives reload")
	PlayerData.switch_deadline = 0
	check(PlayerData.call("equip_owned",7,6).success,"reconfigure fixed last slot")
	check(PlayerData.weapon_slots[6] == 7 and PlayerData.weapon_slots[0] == -1,"no compacting or autofill")
	LevelServer.state = "COMBAT"
	check(not PlayerData.call("clear_loadout").success,"combat cannot edit carry configuration")
	check(not PlayerData.call("remove_slot",6).success,"combat cannot remove slot")
	LevelServer.state = "CAMP"
	# All owned weapons remain reachable through explicit replacement of each fixed slot.
	for id in Utils.weapon_list:
		if not PlayerData.player_weapon_list.has(int(id)): Demo.try_purchase("weapon",id)
	check(PlayerData.player_weapon_list.size() == 24,"all 24 owned")
	PlayerData.clear_loadout()
	for slot in 7:
		PlayerData.switch_deadline = 0
		check(PlayerData.equip_owned(slot,slot).success,"fill fixed slot %d" % slot)
	for slot in 7:
		PlayerData.switch_deadline = 0
		var press = InputEventAction.new(); press.action = "pressed_%d" % (slot+1); press.pressed = true
		Utils.canvasLayer.get_viewport().push_input(press,true)
		await get_tree().process_frame
		var release = InputEventAction.new(); release.action = press.action; release.pressed = false
		Utils.canvasLayer.get_viewport().push_input(release,true)
		check(Utils.player.gun.weapon_id == slot,"actual numbered action %d selects fixed slot" % (slot+1))
	for slot in 7:
		PlayerData.switch_deadline = 0
		var candidate = 111+slot
		check(PlayerData.equip_owned(candidate,slot).success,"replace fixed slot %d" % slot)
		check(PlayerData.weapon_slots[slot] == candidate,"replacement retains exact slot %d" % slot)
	PlayerData.switch_deadline = 0
	check(not PlayerData.equip_owned(124).success,"full loadout requires explicit slot")
	check(PlayerData.equip_owned(124,6).success,"24th weapon can replace final slot")
	PlayerData.player_weapon_list[124].bullets_count = 0
	PlayerData.remove_slot(6)
	var reserve = PlayerData.reserve_magazines
	PlayerData.switch_deadline = 0
	check(PlayerData.equip_owned(124,6).success,"empty magazine can equip")
	await wait(0.3)
	check(PlayerData.player_weapon_list[124].bullets_count == 0 and PlayerData.reserve_magazines == reserve,"camp equip consumes no ammunition")
	var legacy = Demo.snapshot()
	legacy.erase("weapon_slots")
	check(Demo.save_store.save(Demo.save_path,legacy).success and Demo.load_camp(),"legacy file without slots reloads")
	check(PlayerData.weapon_slots.has(124),"legacy current gun beyond first seven stays reachable")
	PlayerData.load_slots({"weapon_slots":[124,124,999,-1,0,"bad",111]})
	check(PlayerData.weapon_slots == [124,-1,-1,-1,0,-1,111],"normalize invalid and duplicate slots without compacting")
	for slot in 7: check(PlayerData.remove_slot(slot).success,"remove each slot including empty %d" % slot)
	check(PlayerData.weapon_slots.count(-1) == 7,"all slots remain empty")
	# Write failure is explicit and retryable, using only the isolated test path.
	Demo.test_mode = false
	Demo.save_blocked = true
	var unsaved = PlayerData.clear_loadout()
	check(unsaved.success and not unsaved.saved and Demo.dirty,"loadout save failure retains dirty retry state")
	Demo.save_blocked = false
	check(Demo.save_camp().success and not Demo.dirty,"retry persists isolated loadout")
	Demo.test_mode = true
	var panel = load("res://ui/CampPanel.gd").new()
	Utils.canvasLayer.add_child(panel)
	await wait(0.1)
	check(panel.loadout_box.get_child_count() == 1,"camp creates compact single carry row")
	check(panel.loadout_box.get_child(0).get_child_count() == 8,"camp renders seven fixed slots and clear action")
	panel.queue_free()
	await wait(0.1)
	complete()

func complete():
	print("B14 SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

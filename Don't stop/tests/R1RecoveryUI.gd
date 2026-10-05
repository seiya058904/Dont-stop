extends Node
class FaultStore extends CampSaveStore:
	func open_temp(_path): return null
class PendingStore extends CampSaveStore:
	var revision = -1
	func save(path, data):
		var result = super.save(path,data)
		return {"success":false,"pending":true,"reason":"正在确认新档"} if result.success else result
	func confirm_web(_path, incoming_revision): revision = incoming_revision
var checks = 0
var failures = 0
func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func frames():
	for frame in 5: await get_tree().process_frame
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-recovery")
	Demo.save_path = "res://evidence/r1-recovery/bad.json"
	var raw = '{"legacy":'
	var file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
	file.store_string(raw); file.close()
	add_child(load("res://game/map/Main.tscn").instantiate())
	# The real start button calls these synchronously in this order.
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; Demo.open_panel()
	await frames()
	check(Demo.pause_stack.back() == Demo.save_dialog and Demo.save_dialog.get_index() > Demo.ui.get_index(),"R03 recovery dialog stays above startup camp panel")
	check(FileAccess.get_file_as_string(Demo.save_path) == raw,"R03 startup keeps corrupt bytes")
	Demo.quit_game(); await frames()
	check(Demo.save_dialog.quitting,"R04 existing recovery prompt gains quit choices")
	var cancel = Demo.save_dialog.find_children("*","Button",true,false).filter(func(b): return b.text == "取消退出")
	check(cancel.size() == 1,"R04 cancel quit remains available")
	if not cancel.is_empty(): cancel[0].pressed.emit()
	else: Demo.save_dialog.queue_free()
	await frames()
	Demo.try_purchase("weapon","0")
	check(Demo.dirty and FileAccess.get_file_as_string(Demo.save_path) == raw,"R03 temporary purchase cannot overwrite bad file")
	var pending = PendingStore.new()
	Demo.save_store = pending
	PlayerData.gold = 333; PlayerData.reward_point = 444
	check(not Demo.create_new_save() and Demo.creating_new_save,"DS-001 new profile remains a pending recovery transaction")
	await frames()
	var dialog = Demo.save_dialog
	var revision = Demo.save_revision
	var before = JSON.stringify(Demo.snapshot())
	check(is_instance_valid(dialog) and Demo.top_pause(dialog),"DS-001 pending transaction owns the recovery pause")
	check(dialog.leave_actions.all(func(b): return b.disabled) and dialog.recovery_actions.all(func(b): return b.disabled),"DS-001 recovery and exit buttons are disabled while pending")
	# Emitting a signal bypasses disabled-button input: callbacks must guard too.
	dialog.leave_actions[0].pressed.emit()
	Demo.quit_game(); Demo.discard_and_leave(); Demo.leave_after_save()
	Demo.show_save_dialog(true,true)
	await frames()
	check(is_instance_valid(dialog) and Demo.save_dialog == dialog and Demo.top_pause(dialog),"DS-001 close, quit and discard cannot release or replace pending recovery")
	check(not Demo.try_purchase("talent","T01").success,"DS-001 pending T01 purchase is rejected before charging")
	check(not Demo.reset_talents(Demo.reset_revision).success and not Demo.unequip_weapon().success,"DS-001 pending reset and unequip are rejected")
	check(not PlayerData.equip_owned(0).success and not PlayerData.remove_slot(0).success and not PlayerData.clear_loadout().success,"DS-001 pending loadout commands are rejected")
	Demo.replenish()
	check(not LevelServer.town.depart(1,true) and not Demo.load_camp(),"DS-001 pending departure and snapshot reload are rejected")
	check(not Demo.save_camp().success and Demo.save_revision == revision and JSON.stringify(Demo.snapshot()) == before,"DS-001 pending commands accept no new state or save revision")
	pending.web_confirmed.emit(revision-1,true,"旧确认")
	check(Demo.creating_new_save and JSON.stringify(Demo.snapshot()) == before,"DS-001 stale confirmation cannot unlock the active transaction")
	pending.web_confirmed.emit(revision,false,"确认失败")
	await frames()
	check(not Demo.creating_new_save and Demo.dirty and Demo.save_blocked,"DS-001 failed confirmation unlocks actions but retains blocked dirty recovery")
	check(FileAccess.get_file_as_string(Demo.save_path) == raw and FileAccess.get_file_as_string(Demo.save_path+".previous") == raw,"DS-001 failed confirmation restores and preserves the original backup")
	check(dialog.leave_actions.all(func(b): return not b.disabled),"DS-001 failed confirmation allows an explicit temporary exit")
	dialog.leave_actions[0].pressed.emit()
	await frames()
	check(not is_instance_valid(Demo.save_dialog),"DS-001 failed recovery can be dismissed")
	check(not Demo.create_new_save() and Demo.creating_new_save,"DS-001 retry reopens and locks a recovery transaction")
	await frames()
	check(is_instance_valid(Demo.save_dialog) and Demo.top_pause(Demo.save_dialog),"DS-001 retry cannot proceed without a recovery dialog")
	pending.web_confirmed.emit(pending.revision,true,"确认完成")
	await frames()
	check(not Demo.creating_new_save and not Demo.save_blocked and not Demo.dirty and not is_instance_valid(Demo.save_dialog),"DS-001 successful confirmation restores the fresh profile before releasing recovery")
	check(Demo.rank("T01") == 0 and PlayerData.gold == DemoConfig.INITIAL_GOLD,"DS-001 no accepted pending purchase is silently overwritten")
	Demo.save_store = CampSaveStore.new()
	var talent = Demo.try_purchase("talent","T01")
	var paid_gold = PlayerData.gold
	check(talent.success and talent.saved and Demo.rank("T01") == 1,"DS-001 post-confirmation purchase is accepted and saved normally")
	check(Demo.load_camp() and Demo.rank("T01") == 1 and PlayerData.gold == paid_gold,"DS-001 post-confirmation purchase survives snapshot reload")
	var durable_revision = Demo.save_revision
	check(Demo.save_before_leave().success and Demo.save_revision == durable_revision,"LEAVE unchanged durable camp reuses snapshot without a revision")
	Demo.save_store = pending
	PlayerData.gold -= 1
	check(Demo.save_before_leave().get("pending",false) and Demo.save_revision == durable_revision+1,"LEAVE real new camp state submits a snapshot")
	var leave_revision = Demo.save_revision
	Demo.quit_game(); await frames()
	check(Demo.waiting_to_leave and Demo.top_pause(Demo) and not is_instance_valid(Demo.save_dialog),"LEAVE pending waits silently with input paused")
	Demo.quit_game()
	check(Demo.save_revision == leave_revision,"LEAVE repeated leave does not resubmit pending snapshot")
	pending.web_confirmed.emit(leave_revision-1,true,"旧确认")
	check(Demo.waiting_to_leave and Demo.dirty,"LEAVE stale confirmation cannot complete leave")
	Demo.discard_and_leave(); Demo.leave_after_save()
	check(Demo.waiting_to_leave and Demo.top_pause(Demo),"LEAVE pending cannot bypass confirmation through another exit callback")
	PlayerData.gold -= 1
	pending.web_confirmed.emit(leave_revision,true,"确认完成")
	check(Demo.waiting_to_leave and Demo.dirty and Demo.save_revision == leave_revision+1 and not is_instance_valid(Demo.save_dialog),"LEAVE confirmation rechecks and saves newer live state before leaving")
	leave_revision = Demo.save_revision
	pending.web_confirmed.emit(leave_revision,false,"确认超时")
	await frames()
	check(not Demo.waiting_to_leave and Demo.dirty and Demo.save_dialog.quitting,"LEAVE timeout opens the full protection dialog")
	check(Demo.save_dialog.leave_actions.size() == 2 and is_instance_valid(Demo.save_dialog.retry),"LEAVE failed pending retains cancel discard and retry")
	Demo.save_dialog.close_dialog(); await frames()
	Demo.save_store = CampSaveStore.new()
	check(Demo.save_camp().success,"LEAVE failed confirmation remains retryable")
	LevelServer.state = "COMBAT"
	Demo.quit_game(); await frames()
	check(not Demo.waiting_to_leave and Demo.dirty and Demo.save_dialog.quitting,"LEAVE combat still requires unsaved-state confirmation")
	Demo.save_dialog.close_dialog(); await frames()
	LevelServer.state = "CAMP"
	Demo.save_store = FaultStore.new()
	var purchase = Demo.try_purchase("weapon","0")
	Demo.quit_game(); await frames()
	check(purchase.success and not purchase.saved and Demo.save_dialog.quitting,"R04 open failure keeps purchased state and blocks exit")
	var gold = PlayerData.gold
	Demo.save_dialog.find_children("*","Button",true,false).filter(func(b): return b.text == "取消退出")[0].pressed.emit()
	await frames()
	check(not is_instance_valid(Demo.save_dialog) and PlayerData.gold == gold and Demo.dirty,"R04 cancel exit preserves unsaved purchase")
	Demo.save_store = CampSaveStore.new()
	check(Demo.save_camp().success and PlayerData.gold == gold,"R04 retry persists without another charge")
	print("R1 RECOVERY UI checks=",checks," failures=",failures)
	Demo.stop_attacks()
	get_tree().quit(1 if failures else 0)

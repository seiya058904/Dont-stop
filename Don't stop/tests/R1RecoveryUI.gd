extends Node
class FaultStore extends CampSaveStore:
	func open_temp(_path): return null
class PendingStore extends CampSaveStore:
	var revision = -1
	func save(path, data):
		var result = super.save(path,data)
		return {"success":false,"pending":true,"reason":"正在确认新档"} if result.success else result
	func confirm_web(_path, incoming_revision): revision = incoming_revision
class RollbackStore extends PendingStore:
	var reject_rollback = false
	var corrupt_after_replace = false
	var rollback_attempts = 0
	func replace_file(source, destination):
		var result = super.replace_file(source,destination)
		if result == OK and corrupt_after_replace:
			var file = FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt-after-takeover"); file.close()
		return result
	func restore_previous(previous_path, temporary, path, text):
		rollback_attempts += 1
		if reject_rollback: return false
		return super.restore_previous(previous_path,temporary,path,text)
var checks = 0
var failures = 0
func check(ok, name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func frames():
	for frame in 5: await get_tree().process_frame

func check_recovery_backup_retries():
	# Both an asynchronous durable failure and a synchronous replacement/readback
	# failure must keep the same authoritative original. These are additions to
	# this existing active case; no acceptance invocation or timeout is changed.
	var raw = PackedByteArray([123,34,120,34,58,255,0,192,175,13,10])
	var scenarios = [
		{"name":"durable","synchronous":false,"backup_fault":""},
		{"name":"durable-missing","synchronous":false,"backup_fault":"missing"},
		{"name":"durable-changed","synchronous":false,"backup_fault":"changed"},
		{"name":"synchronous","synchronous":true,"backup_fault":""}]
	for scenario in scenarios:
		var synchronous = scenario.synchronous
		var mode = scenario.name
		Demo.save_path = "res://evidence/r1-recovery/rollback-"+mode+".json"
		var file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
		file.store_string('{"legacy":'); file.close()
		Demo.test_mode = true
		check(not Demo.load_camp() and Demo.save_blocked,"R03 "+mode+" recovery starts from an actually rejected save")
		# Content validation was exercised above; the recovery/export checks below
		# compare malformed UTF-8 and NUL as bytes, without redundant JSON parsing.
		file = FileAccess.open(Demo.save_path,FileAccess.WRITE)
		file.store_buffer(raw); file.close()
		var before = JSON.stringify(Demo.snapshot())
		var store = RollbackStore.new()
		store.reject_rollback = true
		store.corrupt_after_replace = synchronous
		Demo.save_store = store
		Demo.test_mode = false
		Demo.show_save_dialog(true)
		check(not Demo.create_new_save(),"R03 "+mode+" failed takeover cannot immediately succeed")
		if synchronous:
			check(not Demo.creating_new_save,"R03 synchronous readback failure cannot start a durable confirmation")
		else:
			check(Demo.creating_new_save,"R03 durable takeover waits for confirmation")
			var pending_main = FileAccess.get_file_as_bytes(Demo.save_path)
			if scenario.backup_fault == "missing":
				check(DirAccess.remove_absolute(Demo.save_path+".previous") == OK,"R03 pending missing-backup fault actually removes previous")
			elif scenario.backup_fault == "changed":
				file = FileAccess.open(Demo.save_path+".previous",FileAccess.WRITE)
				file.store_buffer(PackedByteArray([98,97,100,255,0,10])); file.close()
			store.web_confirmed.emit(store.revision,false,"注入持久化失败")
			if not scenario.backup_fault.is_empty():
				await frames()
				check(Demo.dirty and Demo.save_blocked and not Demo.creating_new_save,"R03 "+mode+" failed confirmation retains recovery when previous is unavailable")
				check(FileAccess.get_file_as_bytes(Demo.save_path) == pending_main,"R03 "+mode+" cannot roll altered backup bytes over the staged main")
				var unavailable_export = Demo.export_bad_save()
				check(unavailable_export.begins_with("导出失败"),"R03 "+mode+" unavailable captured original is never replaced by a wrong export")
				check(not Demo.create_new_save() and not Demo.creating_new_save,"R03 "+mode+" missing or changed original cannot start another takeover")
				check(FileAccess.get_file_as_bytes(Demo.save_path) == pending_main,"R03 "+mode+" blocked retry leaves staged main untouched")
				if Demo.creating_new_save: store.web_confirmed.emit(store.revision,false,"不可用原文错误开启事务")
				# Restoring the exact source captured before takeover must re-enable
				# export; this rejects an implementation that pins the damaged bytes
				# only when the delayed failure callback finally arrives.
				file = FileAccess.open(Demo.save_path+".previous",FileAccess.WRITE)
				file.store_buffer(raw); file.close()
		await frames()
		check(store.rollback_attempts > 0 and Demo.save_blocked and not Demo.save_result.success,"R03 "+mode+" rollback failure remains an explicit blocked failure")
		check(FileAccess.get_file_as_bytes(Demo.save_path+".previous") == raw,"R03 "+mode+" previous keeps invalid UTF-8 and NUL exactly")
		var exported = Demo.export_bad_save()
		check(not exported.begins_with("导出失败") and FileAccess.get_file_as_bytes(exported) == raw,"R03 "+mode+" original export stays byte-exact after failed rollback")
		# Damage the already protected backup after the failed rollback. Recovery
		# must refuse it, not redefine that file's new contents as the original.
		var main_before = FileAccess.get_file_as_bytes(Demo.save_path)
		var damaged = PackedByteArray([98,97,100,255,0,10])
		file = FileAccess.open(Demo.save_path+".previous",FileAccess.WRITE)
		file.store_buffer(damaged); file.close()
		exported = Demo.export_bad_save()
		check(exported.begins_with("导出失败"),"R03 "+mode+" mismatched backup cannot be exported as the original")
		store.reject_rollback = false
		check(not Demo.create_new_save() and not Demo.creating_new_save,"R03 "+mode+" mismatched backup cannot release recovery protection")
		check(FileAccess.get_file_as_bytes(Demo.save_path) == main_before and FileAccess.get_file_as_bytes(Demo.save_path+".previous") == damaged,"R03 "+mode+" rejected backup identity leaves both files untouched")
		if Demo.creating_new_save: store.web_confirmed.emit(store.revision,false,"受损备份错误开启事务")
		store.reject_rollback = true
		file = FileAccess.open(Demo.save_path+".previous",FileAccess.WRITE)
		file.store_buffer(raw); file.close()
		exported = Demo.export_bad_save()
		check(not exported.begins_with("导出失败") and FileAccess.get_file_as_bytes(exported) == raw,"R03 "+mode+" restoring exact original bytes restores the export option")
		for attempt in 2:
			check(not Demo.create_new_save(),"R03 "+mode+" unavailable rollback retry cannot succeed "+str(attempt))
			check(FileAccess.get_file_as_bytes(Demo.save_path+".previous") == raw,"R03 "+mode+" retry never recycles fresh bytes over original "+str(attempt))
			exported = Demo.export_bad_save()
			check(not exported.begins_with("导出失败") and FileAccess.get_file_as_bytes(exported) == raw,"R03 "+mode+" retry still exports the actual original "+str(attempt))
			if Demo.creating_new_save: store.web_confirmed.emit(store.revision,false,"再次注入失败")
			await frames()
			check(Demo.save_blocked and not Demo.creating_new_save and JSON.stringify(Demo.snapshot()) == before,"R03 "+mode+" failed retry preserves the live session "+str(attempt))
		store.reject_rollback = false
		store.corrupt_after_replace = false
		check(not Demo.create_new_save() and Demo.creating_new_save,"R03 "+mode+" recovery remains retryable once storage recovers")
		check(FileAccess.get_file_as_bytes(Demo.save_path+".previous") == raw,"R03 "+mode+" final takeover preserves original before confirmation")
		store.web_confirmed.emit(store.revision-1,true,"过期成功")
		check(Demo.creating_new_save and Demo.dirty,"R03 "+mode+" stale success cannot finish the recovery")
		store.web_confirmed.emit(store.revision,true,"最终新档确认")
		await frames()
		check(not Demo.dirty and not Demo.save_blocked and not Demo.creating_new_save and Demo.snapshot().weapons.is_empty(),"R03 "+mode+" latest confirmed retry restores a clean fresh profile")
		var committed = JSON.stringify(Demo.snapshot())
		store.web_confirmed.emit(store.revision,false,"同版本相反失败")
		check(Demo.save_result.success and not Demo.dirty and JSON.stringify(Demo.snapshot()) == committed,"R03 "+mode+" contradictory terminal callback cannot undo a successful recovery")

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
	pending.web_confirmed.emit(revision,true,"同版本相反成功")
	check(Demo.dirty and Demo.save_blocked and not Demo.save_result.success and JSON.stringify(Demo.snapshot()) == before,"DS-001 completed failure cannot be reversed by same-revision success")
	check(FileAccess.get_file_as_string(Demo.save_path) == raw,"DS-001 contradictory success cannot replace the restored original")
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
	var committed = JSON.stringify(Demo.snapshot())
	pending.web_confirmed.emit(pending.revision,false,"同版本相反失败")
	check(Demo.save_result.success and not Demo.dirty and not Demo.save_blocked and JSON.stringify(Demo.snapshot()) == committed,"DS-001 completed success cannot be reversed by same-revision failure")
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
	await check_recovery_backup_retries()
	print("R1 RECOVERY UI checks=",checks," failures=",failures)
	Demo.stop_attacks()
	get_tree().quit(1 if failures else 0)

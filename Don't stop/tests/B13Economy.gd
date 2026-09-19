extends "res://tests/M8Runtime.gd"
## B13 economy contract. Prices express the three qualities in BOTH shops: upgrade price
## bands never overlap, talent rank prices are data-driven and rise per rank, no failed
## purchase ever charges, mixed-currency ledgers refund exactly what was paid, and the
## system-level B13 rule holds: the talent system costs more than the upgrade system.

func _ready():
	await boot()
	# --- upgrade price bands (already asserted per-band in B13Catalog; here: charged) -----
	for key in Utils.am_dict:
		var price := int(AttachmentCatalog.PRICES[int(key)])
		PlayerData.gold = price - 1
		check(not Demo.try_purchase("attachment",key).success and PlayerData.gold == price-1,"underfunded upgrade refuses to charge "+key)
		PlayerData.gold = 100000
		var before: int = PlayerData.gold
		check(Demo.try_purchase("attachment",key).success and PlayerData.gold == before-price,"upgrade charges exactly its catalog price "+key)
	# --- talent charges per rank and currency ---------------------------------------------
	for id in DemoConfig.TALENTS:
		while Demo.rank(id) < DemoConfig.TALENTS[id].max:
			var rank := Demo.rank(id)+1
			var gold: int = PlayerData.gold
			var points: int = PlayerData.reward_point
			check(Demo.try_purchase("talent",id,"gold").success and PlayerData.gold == gold-DemoConfig.talent_gold_price(id,rank),"talent gold charge equals the ladder "+id+"/"+str(rank))
			if rank < DemoConfig.TALENTS[id].max:
				check(Demo.try_purchase("talent",id,"points").success and PlayerData.reward_point == points-DemoConfig.talent_point_price(id,rank+1),"talent point charge equals the ladder "+id+"/"+str(rank+1))
			# A failed currency must not charge: overdraw points mid-ladder.
			if rank == 1 and Demo.rank(id) < DemoConfig.TALENTS[id].max:
				PlayerData.reward_point = 0
				var next_rank := Demo.rank(id)+1
				var gold_now: int = PlayerData.gold
				check(not Demo.try_purchase("talent",id,"points").success and PlayerData.reward_point == 0 and PlayerData.gold == gold_now,"empty point wallet refuses without charge "+id)
				PlayerData.reward_point = 9999
	# --- mixed-currency ledger refunds exactly what was paid -------------------------------
	Demo.replenish()
	LevelServer.state = "CAMP"
	Demo.talents.clear()
	Demo.talent_payments.clear()
	Demo.refresh()
	var build: Dictionary = {"T01":[1,"gold"],"T02":[1,"points"],"T13":[1,"gold"],"T23":[1,"points"],"T14":[1,"gold"]}
	for id in build:
		Demo.try_purchase("talent",id,build[id][1])
	var expected_gold := DemoConfig.talent_gold_price("T01",1)+DemoConfig.talent_gold_price("T13",1)+DemoConfig.talent_gold_price("T14",1)
	var expected_points := DemoConfig.talent_point_price("T02",1)+DemoConfig.talent_point_price("T23",1)
	var preview := Demo.reset_preview()
	check(preview.gold == expected_gold and preview.points == expected_points,"reset preview replays the mixed ledger exactly")
	var gold_before: int = PlayerData.gold
	var points_before: int = PlayerData.reward_point
	check(Demo.reset_talents(preview.revision).success,"reset succeeds")
	check(PlayerData.gold == gold_before+expected_gold and PlayerData.reward_point == points_before+expected_points,"refund returns gold and points separately and exactly")
	check(not Demo.reset_talents(Demo.reset_preview().revision).success,"repeat reset refunds nothing")
	# --- system-level price relation --------------------------------------------------------
	var upgrade_total := 0
	for key in Utils.am_dict: upgrade_total += int(AttachmentCatalog.PRICES[int(key)])
	var talent_total := 0
	for id in DemoConfig.TALENTS:
		for rank in range(1,int(DemoConfig.TALENTS[id].max)+1):
			talent_total += DemoConfig.talent_gold_price(id,rank)
	check(talent_total > upgrade_total,"the full talent build is the more expensive system (%d vs %d)"%[talent_total,upgrade_total])
	# A legendary talent is priced beyond every common upgrade (cross-system ordering the
	# spec demands: the TALENT system is the premium one; per-item the systems keep their
	# own bands - no single-talent-vs-single-upgrade dominance is required).
	var max_common_upgrade := 0
	for key in Utils.am_dict:
		if AttachmentCatalog.quality(int(key)) == 1: max_common_upgrade = maxi(max_common_upgrade,int(AttachmentCatalog.PRICES[int(key)]))
	check(DemoConfig.talent_gold_price("T16",1) > max_common_upgrade,"legendary talent outranks every common upgrade")
	# B13.1 premium relation: a legendary talent costs MORE than the legendary upgrade price
	# band's upper edge. A legend talent is max=1 with no later rank cost, so the whole gold
	# route of the purchase is that one price - it must not undercut the legend upgrades.
	var max_legendary_upgrade := 0
	for key in Utils.am_dict:
		if AttachmentCatalog.quality(int(key)) == 3: max_legendary_upgrade = maxi(max_legendary_upgrade,int(AttachmentCatalog.PRICES[int(key)]))
	for id in DemoConfig.TALENTS:
		if DemoConfig.talent_quality(id) != 3: continue
		check(DemoConfig.talent_gold_price(id,1) > max_legendary_upgrade,"legendary talent %d gold sits above the legendary upgrade band top (%d)"%[DemoConfig.talent_gold_price(id,1),max_legendary_upgrade])
	# --- the INITIAL_GOLD demo rule is untouched --------------------------------------------
	check(DemoConfig.INITIAL_GOLD == 9999,"demo wallet constant unchanged")
	check(DemoConfig.INITIAL_TALENT_POINTS == 9999,"demo talent-point wallet constant unchanged")
	# --- B12-era historical payments refund exactly what was paid ---------------------------
	# The mixed-ledger test above builds its payments at CURRENT B13 prices. That cannot
	# prove anything about real B12 saves, whose ledger amounts were written before the
	# rework. This fixture HARDCODES genuine B12-era amounts (flat 100 gold / 1 point) and
	# must never be regenerated from DemoConfig.talent_gold_price(): if it were, the test
	# would pass even if the refund logic wrongly re-priced old payments. T02 rank 2 rides
	# along as a mixed rank with a currency switch, as a real B12 account could hold.
	Demo.talents = {"T01":1,"T02":2}
	Demo.talent_payments = [
		{"id":"T01","level":1,"currency":"gold","amount":100},
		{"id":"T02","level":1,"currency":"points","amount":1},
		{"id":"T02","level":2,"currency":"gold","amount":130},
	]
	var b13_t01_price: int = DemoConfig.talent_gold_price("T01",1)
	var b13_t02_point_price: int = DemoConfig.talent_point_price("T02",1)
	check(b13_t01_price != 100 and b13_t02_point_price != 1,"fixture sanity: B13 prices differ from the hardcoded B12 amounts (%d gold / %d points)"%[b13_t01_price,b13_t02_point_price])
	Demo.refresh()
	var historic_snapshot: Dictionary = Demo.snapshot()
	check(CampSnapshot.validate(historic_snapshot),"a save carrying B12-era payment amounts validates")
	check(Demo.save_store.save(Demo.save_path,historic_snapshot).success,"write the B12-era save")
	check(Demo.load_camp(),"reload the B12-era save")
	var ledger_after_load: Array = Demo.talent_payments.duplicate(true)
	var ledger_ok := ledger_after_load.size() == 3
	for i in 3:
		if not ledger_ok: break
		for key in ["id","level","currency","amount"]:
			ledger_ok = ledger_ok and str(ledger_after_load[i].get(key)) == str(Demo.talent_payments[i].get(key))
	check(ledger_ok,"loading a B12-era save leaves every payment amount untouched")
	var historic_preview: Dictionary = Demo.reset_preview()
	check(historic_preview.gold == 230 and historic_preview.points == 1,"reset preview replays the historical amounts paid (230 gold = 100+130, 1 point)")
	check(Demo.reset_talents(historic_preview.revision).success,"resetting the historical plan succeeds")
	var gold_after_refund: int = PlayerData.gold
	var points_after_refund: int = PlayerData.reward_point
	check(Demo.talents.is_empty() and Demo.talent_payments.is_empty(),"the historical plan is fully cleared")
	check(Demo.save_store.save(Demo.save_path,Demo.snapshot()).success,"write the post-refund save")
	check(Demo.load_camp(),"reload after the historical refund")
	check(PlayerData.gold == gold_after_refund and PlayerData.reward_point == points_after_refund,"the refunded historical amounts survive a save/reload untouched")
	check(Demo.talents.is_empty() and Demo.talent_payments.is_empty(),"no payment reappears after the reload")
	print("B13_ECONOMY_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

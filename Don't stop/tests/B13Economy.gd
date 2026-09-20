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
		var total = 0
		for level in range(1,DemoConfig.TALENTS[id].max+1): total += DemoConfig.talent_gold_price(id,level)
		check(total > max_legendary_upgrade,"complete legendary talent ladder exceeds legendary upgrade price "+id)
	# --- the INITIAL_GOLD demo rule is untouched --------------------------------------------
	check(DemoConfig.INITIAL_GOLD == 9999,"demo wallet constant unchanged")
	check(DemoConfig.INITIAL_TALENT_POINTS == 9999,"demo talent-point wallet constant unchanged")
	# --- B12-era historical payments refund exactly what was paid ---------------------------
	# The mixed-ledger test above builds its payments at CURRENT B13 prices. That cannot
	# prove anything about real B12 saves, whose ledger amounts were written before the
	# rework. B12's price model (baseline 6bae6e9) was FLAT: `TALENT_GOLD_PRICE = 100` and
	# the purchase path charged exactly `TALENT_GOLD_PRICE if currency == "gold" else 1`
	# for every talent at every rank - so 100 gold / 1 point per rank is the genuine
	# historical amount, including a rank-2 purchase. This fixture HARDCODES those amounts
	# (never regenerated from DemoConfig.talent_gold_price): if it were, the test would
	# pass even if the refund logic wrongly re-priced old payments.
	var historic_payments := [
		{"id":"T01","level":1,"currency":"gold","amount":100},
		{"id":"T02","level":1,"currency":"points","amount":1},
		{"id":"T02","level":2,"currency":"gold","amount":100},
	]
	check(DemoConfig.talent_gold_price("T01",1) != 100,"fixture sanity: T01 rank-1 B13 gold price (%d) is not the historical 100"%DemoConfig.talent_gold_price("T01",1))
	check(DemoConfig.talent_gold_price("T02",2) != 100,"fixture sanity: T02 rank-2 B13 gold price (%d) is not the historical flat 100"%DemoConfig.talent_gold_price("T02",2))
	check(DemoConfig.talent_point_price("T02",1) != 1,"fixture sanity: T02 rank-1 B13 point price (%d) is not the historical 1"%DemoConfig.talent_point_price("T02",1))
	Demo.talents = {"T01":1,"T02":2}
	Demo.talent_payments = historic_payments.duplicate(true)
	Demo.refresh()
	var historic_snapshot: Dictionary = Demo.snapshot()
	check(CampSnapshot.validate(historic_snapshot),"a save carrying B12-era payment amounts validates")
	check(Demo.save_store.save(Demo.save_path,historic_snapshot).success,"write the B12-era save")
	check(Demo.load_camp(),"reload the B12-era save")
	# Compare against the HARDCODED history, not against Demo.talent_payments itself:
	# comparing two post-load copies would prove nothing about what load did.
	var ledger_ok: bool = Demo.talent_payments.size() == historic_payments.size()
	for i in historic_payments.size():
		if not ledger_ok: break
		# id/currency compare exactly; level/amount compare numerically because the JSON
		# round-trip hands back 100.0 for the stored 100 - a re-priced 150 would still fail.
		for key in ["id","currency"]:
			ledger_ok = ledger_ok and str(Demo.talent_payments[i].get(key)) == str(historic_payments[i][key])
		for key in ["level","amount"]:
			ledger_ok = ledger_ok and is_equal_approx(float(Demo.talent_payments[i].get(key,0.0)),float(historic_payments[i][key]))
	check(ledger_ok,"loading a B12-era save leaves every hardcoded payment amount untouched (100 gold / 1 point / 100 gold)")
	var historic_gold_before: int = PlayerData.gold
	var historic_points_before: int = PlayerData.reward_point
	var historic_preview: Dictionary = Demo.reset_preview()
	check(historic_preview.gold == 200 and historic_preview.points == 1,"reset preview replays the historical amounts paid (200 gold = 100+100, 1 point)")
	check(Demo.reset_talents(historic_preview.revision).success,"resetting the historical plan succeeds")
	check(PlayerData.gold == historic_gold_before+200 and PlayerData.reward_point == historic_points_before+1,"the real wallet delta is exactly the historical refund (+200 gold / +1 point)")
	check(Demo.talents.is_empty() and Demo.talent_payments.is_empty(),"the historical plan is fully cleared")
	check(Demo.save_store.save(Demo.save_path,Demo.snapshot()).success,"write the post-refund save")
	check(Demo.load_camp(),"reload after the historical refund")
	check(PlayerData.gold == historic_gold_before+200 and PlayerData.reward_point == historic_points_before+1,"the refunded historical amounts survive a save/reload untouched")
	check(Demo.talents.is_empty() and Demo.talent_payments.is_empty(),"no payment reappears after the reload")
	var empty_preview: Dictionary = Demo.reset_preview()
	check(empty_preview.gold == 0 and empty_preview.points == 0,"reset preview of the cleared account is 0 gold / 0 points")
	print("B13_ECONOMY_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

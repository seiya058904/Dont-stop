extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	Demo.save_path = "user://b16-t09-isolated.json"
	configure(0)
	for old_rank in [0,1,2,3]:
		for payment_mode in ["gold","points","mixed","unknown"]:
			Demo.talents = {"T09":old_rank} if old_rank else {}
			Demo.talent_payments = []
			var expected_gold = 0
			var expected_points = 0
			if payment_mode != "unknown":
				for rank in range(1,old_rank+1):
					var currency = "points" if payment_mode == "points" or (payment_mode == "mixed" and rank == 2) else "gold"
					var amount = [150,250,350][rank-1] if currency == "gold" else [1,1,2][rank-1]
					Demo.talent_payments.append({"id":"T09","level":rank,"currency":currency,"amount":amount})
					if currency == "gold": expected_gold += amount
					else: expected_points += amount
			var data = Demo.snapshot()
			check(CampSnapshot.validate(data),"old T09 validates %d %s" % [old_rank,payment_mode])
			check(Demo.save_store.save(Demo.save_path,data).success and Demo.load_camp(),"old T09 file restores")
			check(Demo.rank("T09") == old_rank,"old T09 rank preserved")
			var refund = Demo.reset_preview()
			check(refund.gold == expected_gold and refund.points == expected_points,"refund replays old prices, never new legendary prices")
			check(refund.unknown == (old_rank if payment_mode == "unknown" else 0),"missing payment stays explicitly unknown")
	print("B16 SAVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

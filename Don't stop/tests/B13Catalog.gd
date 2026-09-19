extends "res://tests/M8Runtime.gd"
## B13 catalog contract. Both growth systems (24 one-shot global upgrades, 24 talents) carry
## exactly three player-visible qualities (普通/稀有/传说), names describe the actual effect
## in all-weapon language, prices are data-driven and strictly banded, and the ID namespace
## the save keys ownership on is untouched.

func _ready():
	await boot()
	# --- upgrade catalog shape -----------------------------------------------------------
	check(Utils.am_dict.size()==24,"exactly 24 upgrade definitions")
	var seen := {}
	for key in Utils.am_dict:
		var id := int(key)
		check(not seen.has(id),"no duplicate upgrade id "+key)
		seen[id] = true
		var d: Dictionary = AttachmentCatalog.DEFINITIONS[id]
		check(AttachmentCatalog.display_name(id) != "","upgrade name present "+key)
		check(d.get("info","") != "","upgrade info present "+key)
		var q := AttachmentCatalog.quality(id)
		check(q==1 or q==2 or q==3,"upgrade quality inside 1..3 "+key)
		var price := int(AttachmentCatalog.PRICES[id])
		check(price>0,"positive upgrade price "+key)
		# The shop charges the scene money getter; it must keep reading the catalog.
		var am = Utils.am_dict[key].instantiate()
		check(int(am.money)==price,"shop price is the catalog price "+key)
		check(tr(am.am_name)==AttachmentCatalog.display_name(id),"scene display name matches catalog "+key)
		am.free()
		# Every upgrade must carry at least one real effect key beyond the metadata.
		var effects := 0
		for effect_key in ["damage","damage_mul","crit","magazine_mul","reload_mul","range_mul","spread_mul","impulse_mul","radius_mul","width_mul","angle_mul","turn_mul","lock_mul","warmup_mul","recovery_mul","pierce","bounces","shards","jumps","refill"]:
			if d.has(effect_key): effects += 1
		check(effects>0,"upgrade declares at least one effect "+key)
	# --- upgrade quality bands do not overlap --------------------------------------------
	for q in range(1,3):
		var lows: Array = []
		var highs: Array = []
		for key in Utils.am_dict:
			if AttachmentCatalog.quality(int(key))==q: lows.append(int(AttachmentCatalog.PRICES[int(key)]))
			if AttachmentCatalog.quality(int(key))==q+1: highs.append(int(AttachmentCatalog.PRICES[int(key)]))
		check(lows.size()>0 and highs.size()>0,"both upgrade quality bands populated %d/%d"%[q,q+1])
		check(int(maxv(lows))<int(minv(highs)),"upgrade quality %d price band strictly below %d"%[q,q+1])
	for q in [1,2,3]:
		var members := 0
		for key in Utils.am_dict:
			if AttachmentCatalog.quality(int(key))==q: members += 1
		check(members>0,"upgrade quality %d is populated"%q)
	# --- talent catalog shape --------------------------------------------------------------
	check(DemoConfig.TALENTS.size()==24,"exactly 24 talent definitions")
	for id in DemoConfig.TALENTS:
		var d: Dictionary = DemoConfig.TALENTS[id]
		check(d.get("name","") != "","talent name present "+id)
		check(DemoConfig.talent_info(id) != "","talent info present "+id)
		var q := DemoConfig.talent_quality(id)
		check(q==1 or q==2 or q==3,"talent quality inside 1..3 "+id)
		var max_rank: int = int(d.max)
		check(max_rank>=1 and max_rank<=3,"talent max rank inside 1..3 "+id)
		for rank in range(1,max_rank+1):
			check(DemoConfig.talent_gold_price(id,rank)>0,"talent gold price present "+id+"/"+str(rank))
			check(DemoConfig.talent_point_price(id,rank)>0,"talent point price present "+id+"/"+str(rank))
			if rank>1:
				check(DemoConfig.talent_gold_price(id,rank)>DemoConfig.talent_gold_price(id,rank-1),"talent gold price rises per rank "+id)
				check(DemoConfig.talent_point_price(id,rank)>=DemoConfig.talent_point_price(id,rank-1),"talent point price never falls "+id)
		check(DemoConfig.talent_gold_price(id,1)<=DemoConfig.talent_gold_price(id,max_rank),"talent price ladder sane "+id)
	for q in [1,2,3]:
		var members := 0
		for id in DemoConfig.TALENTS:
			if DemoConfig.talent_quality(id)==q: members += 1
		check(members>0,"talent quality %d is populated"%q)
	# --- talent quality price bands do not overlap (same rank comparison) ------------------
	for rank in [1,2,3]:
		var commons: Array = []
		var rares: Array = []
		var legends: Array = []
		for id in DemoConfig.TALENTS:
			if int(DemoConfig.TALENTS[id].max) < rank: continue
			match DemoConfig.talent_quality(id):
				1: commons.append(DemoConfig.talent_gold_price(id,rank))
				2: rares.append(DemoConfig.talent_gold_price(id,rank))
				3: legends.append(DemoConfig.talent_gold_price(id,rank))
		if not commons.is_empty() and not rares.is_empty():
			check(int(maxv(commons))<int(minv(rares)),"talent common band below rare band at rank %d"%rank)
		if not rares.is_empty() and not legends.is_empty():
			check(int(maxv(rares))<int(minv(legends)),"talent rare band below legendary band at rank %d"%rank)
	# --- B13 system rule: talents are the more expensive growth system ----------------------
	var upgrade_total := 0
	for key in Utils.am_dict: upgrade_total += int(AttachmentCatalog.PRICES[int(key)])
	var talent_total := 0
	for id in DemoConfig.TALENTS:
		for rank in range(1,int(DemoConfig.TALENTS[id].max)+1):
			talent_total += DemoConfig.talent_gold_price(id,rank)
	check(talent_total>upgrade_total,"full talent build costs more gold than the full upgrade build")
	# --- ID stability: the save namespace is unchanged --------------------------------------
	var snapshot: Dictionary = Demo.snapshot()
	check(CampSnapshot.validate(snapshot),"a snapshot with the reworked catalog still validates")
	print("B13_CATALOG_CHECKS ",checks," FAILURES ",failures)
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

extends RefCounted
class_name CampSnapshot

static func number(value, integral = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and (not integral or value == floor(value)) and value <= 9007199254740991.0

static func validate(data) -> bool:
	if not data is Dictionary: return false
	if not data.has_all(["schema_version","gold","points","level","exp","hp","hp_max","weapons","talents","next_stage","selected_stage","equipped"]): return false
	if not number(data.schema_version,true) or int(data.schema_version) not in [1,2,3,4,5,6]: return false
	if data.schema_version < 6:
		if not data.get("attachments") is Array or not number(data.get("next_instance"),true): return false
	else:
		if data.has("attachments") or data.has("next_instance") or not data.get("owned_global_upgrades") is Array: return false
		var seen = {}
		for id in data.owned_global_upgrades:
			if not id is String or not Utils.am_dict.has(id) or seen.has(id): return false
			seen[id] = true
	var reserve_key = "reserve_magazines" if data.schema_version >= 5 else "ammo"
	if not number(data.get(reserve_key),true): return false
	if data.schema_version >= 4 and not data.get("campaign_complete") is bool: return false
	for key in ["gold","points","level","next_stage","selected_stage"]:
		if not number(data[key],true): return false
	for key in ["hp","hp_max","exp"]:
		if not number(data[key]): return false
	if data.level < 1 or data.hp_max <= 0 or data.hp > data.hp_max or data.exp >= pow(data.level,2.2)+15: return false
	if not DemoConfig.ENCOUNTERS.has(int(data.next_stage)) or not DemoConfig.ENCOUNTERS.has(int(data.selected_stage)): return false
	if not data.weapons is Array or not data.talents is Dictionary: return false
	if not data.get("legacy",[]) is Array or (data.schema_version >= 2 and not data.has_all(["legacy","legacy_state"])): return false
	for id in data.talents:
		if not DemoConfig.TALENTS.has(id) or not number(data.talents[id],true) or data.talents[id] > DemoConfig.TALENTS[id].max: return false
	if data.schema_version >= 3:
		if not data.get("talent_payments") is Array: return false
		var paid_levels = []
		for payment in data.talent_payments:
			if not payment is Dictionary or not payment.has_all(["id","level","currency","amount"]): return false
			if not payment.id is String or not data.talents.has(payment.id) or payment.currency not in ["gold","points"]: return false
			if not number(payment.level,true) or payment.level < 1 or payment.level > data.talents[payment.id] or not number(payment.amount,true) or payment.amount <= 0: return false
			var key = payment.id+":"+str(int(payment.level))
			if key in paid_levels: return false
			paid_levels.append(key)

	var counts = {}
	for id in data.get("legacy",[]):
		if not id is String or not RewardServer.reward_list.has(id): return false
		counts[id] = counts.get(id,0)+1
	for id in counts:
		var reward = RewardServer.reward_list[id].instantiate()
		var valid = reward.only_start or counts[id] <= reward.max_count
		reward.free()
		if not valid: return false
	var state = data.get("legacy_state",{})
	if not state is Dictionary: return false
	for id in state:
		if not counts.has(id): return false
		if id == "10":
			if not number(state[id],true) or state[id] > 1000: return false
		elif id in ["8","9"]:
			if not state[id] is Dictionary or not number(state[id].get("remaining",-1),false) or state[id].remaining>6: return false
			if id == "8" and (not number(state[id].get("kills",-1),true) or not number(state[id].get("window",-1),false) or state[id].window>1): return false
			if id == "9" and not state[id].get("charged",null) is bool: return false
		elif id in ["12","13","14","15","16","17","18","19","20","21","22","23"]:
			if not state[id] is Dictionary or not state[id].has_all(["hits","kills","cooldown","armed","move_time","moving_buff"]): return false
			for key in ["hits","kills","cooldown","move_time"]:
				if not number(state[id][key],key in ["hits","kills"]) or state[id][key] > 100: return false
			if not state[id].armed is bool or not state[id].moving_buff is bool: return false
		else: return false
	if data.schema_version >= 2 and counts.has("10") and not state.has("10"): return false
	var guns = {}
	var items = []
	var valid = true
	for w in data.weapons:
		if not w is Dictionary or not w.has_all(["id","ammo"]) or not w.id is String or not Utils.weapon_list.has(w.id) or guns.has(w.id) or not number(w.ammo,true):
			valid = false; break
		var gun = Utils.weapon_list[w.id].instantiate()
		gun.tags = DemoConfig.weapon_tags(int(w.id))
		gun.base_stats = {"damage":gun.damage,"magazine":gun.bullets_max_count,"reload":gun.change_speed,"rate":gun.fire_rate,"impulse":gun.knockback_speed}
		guns[w.id] = gun
	var ids = []
	var slots = {}
	if data.schema_version < 6 and data.next_instance < 1: valid = false
	if valid:
		for a in data.get("attachments",[]):
			if not a is Dictionary or not a.has_all(["definition","instance","gun"]) or not a.definition is String or not Utils.am_dict.has(a.definition) or not a.gun is String or not number(a.instance,true):
				valid = false; break
			if a.instance < 1 or a.instance >= data.next_instance or a.instance in ids or (a.gun != "" and not guns.has(a.gun)):
				valid = false; break
			ids.append(a.instance)
			var am = Utils.am_dict[a.definition].instantiate()
			items.append(am)
			if a.gun != "":
				var slot = a.gun+":"+am.am_type
				if slots.has(slot) or not am.can_equip(guns[a.gun]):
					valid = false; break
				slots[slot] = true
				guns[a.gun].attachments_dict[am.am_type] = am
	if valid:
		for w in data.weapons:
			var gun = guns[w.id]
			var upgrades = data.owned_global_upgrades if data.schema_version >= 6 else gun.attachments_dict.values()
			if data.schema_version >= 5 and w.ammo > EffectiveStats.calculate(gun,upgrades,data).magazine: valid = false
	for am in items: am.free()
	for gun in guns.values(): gun.free()
	if not data.equipped is String or (data.equipped != "" and not guns.has(data.equipped)): valid = false
	return valid

static func normalize(data: Dictionary) -> Dictionary:
	var result = data.duplicate(true)
	result.campaign_complete = data.get("campaign_complete",false)
	# B批: Hell Mode completion is an OPTIONAL field. schema_version stays 6, so every old
	# save still validates (validate() does not require the key) and no namespace changed.
	result.hell_complete = data.get("hell_complete",false)
	# The Stage-30 -> Stage-31 migration lives here, between validate() and the restore, so
	# it needs no schema bump: validate() runs first and stage 30 is still a legal stage, and
	# stage 31 exists for every save written after this batch.
	# B11: `next_stage` is the LINEAR CAMPAIGN pointer, and the only thing this file may do to it
	# is keep it inside the stage table (1-40) and migrate the historical 30 -> 31 step for a save
	# that had already finished the normal campaign. It is NOT a selectability gate any more: every
	# stage is permanently choosable on any save, so a fresh save holding a Hell
	# `next_stage` is a state the product accepts and there is nothing to rewrite. The previous
	# version clamped an unfinished save to 30, which silently discarded a legal pointer -- and,
	# worse, silently rewrote the terminal Stage-40 state of a save that had cleared Hell without
	# clearing the normal campaign first.
	result.next_stage = clampi(int(result.next_stage),1,40)
	if result.campaign_complete and int(result.next_stage) == 30 and DemoConfig.ENCOUNTERS.has(31):
		result.next_stage = 31
	# B11: `selected_stage` is only bounded by the stage table (1-40), never by progress.
	# Every stage is permanently selectable on a fresh save, so a Hell selection is a state the
	# product accepts and there is nothing to rewrite here. `next_stage` below keeps its clamp
	# because it is the LINEAR CAMPAIGN pointer - a fresh save's story really does resume at
	# Stage 30 at the latest - and not a selectability gate.
	result.selected_stage = clampi(int(result.selected_stage),1,40)
	result.talent_payments = data.get("talent_payments",[]).duplicate(true) if data.schema_version >= 3 else []
	result.legacy = data.get("legacy",[]).duplicate()
	result.legacy_state = data.get("legacy_state",{}).duplicate()
	if data.schema_version == 1 and "10" in result.legacy:
		# v1 persisted HP growth, but omitted the bacteria's lifetime counter.
		var base_hp = 5.0 + 0.5*(data.level-1) + 3.0*result.legacy.count("2")
		result.legacy_state["10"] = clampi(roundi((data.hp_max-base_hp)/0.1),0,1000)
	if data.schema_version < 5:
		var capacity = 30
		if Utils.weapon_list.has(data.equipped):
			var gun = Utils.weapon_list[data.equipped].instantiate()
			capacity = gun.bullets_max_count
			for a in data.attachments:
				if a.gun == data.equipped: capacity += {"1":10,"2":20,"3":10,"5":5,"6":50,"7":19,"8":70}.get(a.definition,0)
			capacity = maxi(1,int(capacity*(1.0+DemoConfig.talent_value("T04",int(data.talents.get("T04",0))))))
			gun.free()
		result.reserve_magazines = ceili(float(data.ammo)/capacity)
		result.erase("ammo")
		# Capacity buffs changed to percentages. Keep every item, clamp loaded rounds only.
		for w in result.weapons:
			var gun = Utils.weapon_list[w.id].instantiate()
			gun.tags = DemoConfig.weapon_tags(int(w.id))
			gun.base_stats = {"damage":gun.damage,"magazine":gun.bullets_max_count,"reload":gun.change_speed,"rate":gun.fire_rate,"impulse":gun.knockback_speed}
			var items = []
			for a in result.attachments:
				if a.gun == w.id: items.append(Utils.am_dict[a.definition].instantiate())
			w.ammo = mini(int(w.ammo),EffectiveStats.calculate(gun,items,result).magazine)
			for am in items: am.free()
			gun.free()
	var upgrades = result.get("owned_global_upgrades",[]).duplicate()
	for a in result.get("attachments",[]):
		if not a.definition in upgrades: upgrades.append(a.definition)
	upgrades.sort()
	result.owned_global_upgrades = upgrades
	result.erase("attachments"); result.erase("next_instance"); result.erase("compatibility")
	result.schema_version = 6
	return result

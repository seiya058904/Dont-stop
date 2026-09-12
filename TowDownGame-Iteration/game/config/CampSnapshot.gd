extends RefCounted
class_name CampSnapshot

static func number(value, integral = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and (not integral or value == floor(value)) and value <= 9007199254740991.0

static func validate(data) -> bool:
	if not data is Dictionary: return false
	if not data.has_all(["schema_version","gold","points","ammo","level","exp","hp","hp_max","weapons","attachments","talents","next_instance","next_stage","selected_stage","equipped"]): return false
	if data.schema_version != 1 and data.schema_version != 2: return false
	for key in ["gold","points","ammo","level","next_instance","next_stage","selected_stage"]:
		if not number(data[key],true): return false
	for key in ["hp","hp_max","exp"]:
		if not number(data[key]): return false
	if data.level < 1 or data.hp_max <= 0 or data.hp > data.hp_max or data.exp >= pow(data.level,2.2)+15: return false
	if not DemoConfig.ENCOUNTERS.has(int(data.next_stage)) or not DemoConfig.ENCOUNTERS.has(int(data.selected_stage)): return false
	if not data.weapons is Array or not data.attachments is Array or not data.talents is Dictionary: return false
	if not data.get("legacy",[]) is Array or (data.schema_version == 2 and not data.has_all(["legacy","legacy_state"])): return false
	for id in data.talents:
		if not DemoConfig.TALENTS.has(id) or not number(data.talents[id],true) or data.talents[id] > DemoConfig.TALENTS[id].max: return false
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
		if id != "10" or not counts.has(id) or not number(state[id],true) or state[id] > 1000: return false
	if data.schema_version == 2 and counts.has("10") and not state.has("10"): return false
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
	if data.next_instance < 1: valid = false
	if valid:
		for a in data.attachments:
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
			if w.ammo > EffectiveStats.calculate(gun,gun.attachments_dict.values(),data).magazine: valid = false
	for am in items: am.free()
	for gun in guns.values(): gun.free()
	if not data.equipped is String or (data.equipped != "" and not guns.has(data.equipped)): valid = false
	return valid

static func normalize(data: Dictionary) -> Dictionary:
	var result = data.duplicate(true)
	result.legacy = data.get("legacy",[]).duplicate()
	result.legacy_state = data.get("legacy_state",{}).duplicate()
	if data.schema_version == 1 and "10" in result.legacy:
		# v1 persisted HP growth, but omitted the bacteria's lifetime counter.
		var base_hp = 5.0 + 0.5*(data.level-1) + 3.0*result.legacy.count("2")
		result.legacy_state["10"] = clampi(roundi((data.hp_max-base_hp)/0.1),0,1000)
	return result

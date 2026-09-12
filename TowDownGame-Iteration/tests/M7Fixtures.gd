extends RefCounted
class_name M7Fixtures
# Historical fixtures still serialize bullet reserves. New-schema fixtures never do.
static func legacy(snapshot: Dictionary, version: int) -> Dictionary:
	var data = snapshot.duplicate(true)
	var capacity = 30
	if Utils.weapon_list.has(data.equipped):
		var gun = Utils.weapon_list[data.equipped].instantiate(); capacity = gun.bullets_max_count; gun.free()
		for a in data.attachments:
			if a.gun == data.equipped: capacity += {"1":10,"2":20,"3":10,"5":5,"6":50,"7":19,"8":70}.get(a.definition,0)
		capacity = maxi(1,int(capacity*(1.0+DemoConfig.talent_value("T04",int(data.talents.get("T04",0))))))
	data.ammo = int(data.get("reserve_magazines",10))*capacity
	data.erase("reserve_magazines")
	data.schema_version = version
	return data

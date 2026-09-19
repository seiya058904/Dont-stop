extends "res://tests/M8Runtime.gd"

func numeric_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result = {}
	for key in after:
		if after[key] is float or after[key] is int:
			var difference = float(after[key])-float(before.get(key,0))
			if not is_zero_approx(difference): result[key]=difference
	return result

func _ready():
	await boot()
	var tag="after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):tag=arg.substr(6)
	var rows = []
	var all_upgrades = []
	var all_talents = {}
	for id in AttachmentCatalog.DEFINITIONS: all_upgrades.append(str(id))
	for id in DemoConfig.TALENTS: all_talents[id]=DemoConfig.TALENTS[id].max
	for id in WeaponCatalog.TIERS:
		configure(id)
		var gun = Utils.player.gun
		for level in [1,20]:
			PlayerData.player_level=level
			Demo.talents={} if level==1 else all_talents.duplicate()
			Demo.kill_stacks=0
			var owned=[] if level==1 else all_upgrades.duplicate()
			var baseline=EffectiveStats.calculate(gun,owned)
			for upgrade in all_upgrades:
				var comparison=owned.duplicate()
				if level==1: comparison.append(upgrade)
				else: comparison.erase(upgrade)
				var other=EffectiveStats.calculate(gun,comparison)
				rows.append({"weapon":id,"level":level,"kind":"upgrade","id":upgrade,"comparison":"add to bare" if level==1 else "remove from full account","baseline":baseline,"delta":numeric_delta(baseline,other) if level==1 else numeric_delta(other,baseline)})
			for talent in all_talents:
				var saved_ranks=Demo.talents.duplicate()
				if level==1: Demo.talents[talent]=all_talents[talent]
				else: Demo.talents.erase(talent)
				var other=EffectiveStats.calculate(gun,owned)
				rows.append({"weapon":id,"level":level,"kind":"talent","id":talent,"comparison":"max rank added to bare" if level==1 else "max rank removed from full account","delta":numeric_delta(baseline,other) if level==1 else numeric_delta(other,baseline),"note":"passive stat observation only; conditional, utility and survival effects require event tests"})
				Demo.talents=saved_ranks
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-growth-matrix-"+tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"));file.close()
	print("B14_GROWTH_MATRIX rows=",rows.size()," passive observations; not combat passes")
	var catalog={"weapons":[],"upgrades":[],"talents":[]}
	for id in WeaponCatalog.TIERS:
		var gun=PlayerData.player_weapon_list[id]
		catalog.weapons.append({"id":id,"name":TranslationServer.translate(gun.weapon_name),"tier":WeaponCatalog.tier(id),"price":WeaponCatalog.PRICES[str(id)],"definition":WeaponCatalog.definition(id),"tags":gun.tags})
	for id in AttachmentCatalog.DEFINITIONS:
		catalog.upgrades.append({"id":id,"definition":AttachmentCatalog.DEFINITIONS[id],"tier":AttachmentCatalog.quality(id),"price":AttachmentCatalog.PRICES[id]})
	for id in DemoConfig.TALENTS:
		catalog.talents.append({"id":id,"definition":DemoConfig.TALENTS[id],"info":DemoConfig.talent_info(id),"tier":DemoConfig.talent_quality(id),"gold":DemoConfig.TALENT_GOLD_PRICES[DemoConfig.talent_quality(id)],"points":DemoConfig.TALENT_POINT_PRICES[DemoConfig.talent_quality(id)]})
	file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-catalog-"+tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog,"\t"));file.close()
	get_tree().quit.call_deferred()

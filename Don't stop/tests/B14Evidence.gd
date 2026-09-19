extends "res://tests/M8Runtime.gd"
## B14 replaces the B12 static-GPS and B13 rifle-only balance expectations,
## not their historical data. Invoked explicitly with --b14 by those contracts.
var scope="weapons"
const ROOT="res://docs/iteration/evidence/b14/"

func json_file(name):
	var path=ROOT+name
	if not FileAccess.file_exists(path):return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _ready():
	await boot()
	var manifest=json_file("manifest.json")
	check(manifest is Dictionary,"B14 current-source and raw-evidence manifest exists")
	if not manifest is Dictionary: get_tree().quit(1);return
	for category in ["source","data"]:
		for entry in manifest[category]:
			var path="res://"+entry.path
			check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).replace("\r\n","\n").sha256_text()==entry.sha256,"B14 "+category+" fingerprint "+entry.path)
	if scope=="growth":
		var matrix=json_file("b14-growth-matrix-release.json")
		check(matrix is Array and matrix.size()==2304,"24 weapons x 48 growth items x 2 states observed")
		if matrix is Array:
			var keys={}
			for row in matrix:keys[str(row.weapon)+":"+str(row.level)+":"+row.kind+":"+str(row.id)]=true
			check(keys.size()==2304,"no duplicated growth observation substitutes for a missing item")
			for id in WeaponCatalog.TIERS:
				var cycle=matrix.filter(func(r):return int(r.weapon)==id and r.kind=="talent" and r.id=="T02" and int(r.level)==1)
				check(cycle.size()==1 and (cycle[0].delta.get("damage",0)>0 or cycle[0].delta.get("rate",0)>0),"purchased cycle has a real stat path on weapon %d"%id)
		check(AttachmentCatalog.quality(119)==2 and AttachmentCatalog.quality(122)==2 and AttachmentCatalog.quality(123)==2,"narrow specialist upgrades no longer priced legendary")
	else:
		var rows=json_file("b14-horde-reference.json")
		var after=json_file("b14-horde-calibrated.json")
		check(rows is Array and rows.size()==48,"complete 24-weapon bare/late moving reference retained")
		check(after is Array and after.size()==6,"all three parameter changes have paired moving remeasurement")
		if not rows is Array or not after is Array:get_tree().quit(1);return
		var latest={}
		for row in rows+after:latest[str(int(row.id))+":"+row.build]=row
		check(latest.size()==48,"current coverage contains all 24 weapons and both builds")
		for id in WeaponCatalog.TIERS:
			configure(id)
			for build_name in ["bare","late"]:
				var row=latest.get(str(id)+":"+build_name,{})
				check(not row.is_empty(),"moving result exists %d/%s"%[id,build_name])
				if row.is_empty():continue
				check(row.seed==20260920 and row.seconds>=14.9 and row.movement>100 and row.hit_events>0 and row.ammo_used>0,"same timed real movement/firing protocol %d/%s"%[id,build_name])
				PlayerData.player_level=int(row.level);Demo.talents=row.talents;Demo.owned_global_upgrades=row.upgrades
				var matches=false
				# Recorded row is the END snapshot; legal T10 stacks are 0..5.
				# Do not silently compare that snapshot to an unstacked paper build.
				for stacks in 6:
					Demo.kill_stacks=stacks
					var actual=EffectiveStats.calculate(Utils.player.gun)
					var equal=true
					for key in ["damage","magazine","reload","rate","range","width","warmup","radius"]:
						if not is_equal_approx(float(actual[key]),float(row.effective[key])):equal=false
					if equal:matches=true
				check(matches,"recorded combat parameters cover current product %d/%s"%[id,build_name])
				if WeaponCatalog.tier(id)==5:
					check(row.kills>=75 if build_name=="bare" else row.kills>=85,"legendary sustains ordinary-horde clearing in fixed protocol %d/%s"%[id,build_name])
		var encounters=json_file("b14-encounter-after2.json")+json_file("b14-encounter-coverage.json")
		check(encounters.size()==5,"five representative late encounters measured")
		for row in encounters:
			check(row.ordinary_alive_time_fraction>=0.8 and row.ordinary_spawn_fraction>=0.8,"real late encounter is ordinary-led stage %d"%row.stage)
			check(row.completed and not row.dead and row.movement>1000,"normal-health autonomous encounter completed stage %d"%row.stage)
	print("B14_EVIDENCE_",scope.to_upper()," CHECKS ",checks," FAILURES ",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

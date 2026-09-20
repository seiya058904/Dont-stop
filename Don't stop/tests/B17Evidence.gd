extends "res://tests/M8Runtime.gd"
## Current evidence is versioned independently; B14 remains frozen and runnable.
var scope="growth"
const ROOT="res://docs/iteration/evidence/b17/"

func json_file(name):
	if not FileAccess.file_exists(ROOT+name): return null
	return JSON.parse_string(FileAccess.get_file_as_string(ROOT+name))

func _ready():
	await boot()
	var manifest=json_file("manifest.json")
	check(manifest is Dictionary,"B17 manifest exists")
	if not manifest is Dictionary: get_tree().quit(1); return
	for category in ["source","data"]:
		check(manifest.get(category,[]).size()>0,"nonempty manifest category "+category)
		for entry in manifest.get(category,[]):
			var path="res://"+entry.path
			check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).replace("\r\n","\n").sha256_text()==entry.sha256,"B17 "+category+" fingerprint "+entry.path)
	var sources=json_file("sources.json")
	check(sources is Dictionary and sources.rows.size()==72 and sources.failures==0,"72 registered sources plus independent HP and transaction tests")
	var rewards=json_file("reward-matrix.json")
	check(rewards is Dictionary and rewards.rows.size()==24 and rewards.failures==0,"24 prototype direct-event observations")
	var matrix=json_file("growth-matrix.json")
	check(matrix is Array and matrix.size()==2304,"24 weapons x 48 growth items x 2 states observed")
	if matrix is Array:
		var keys={}
		for row in matrix: keys[str(row.weapon)+":"+str(row.level)+":"+row.kind+":"+str(row.id)]=true
		check(keys.size()==2304,"no duplicate growth rows")
		for id in WeaponCatalog.TIERS:
			var cycle=matrix.filter(func(r): return int(r.weapon)==id and r.kind=="talent" and r.id=="T02" and int(r.level)==1)
			check(cycle.size()==1 and (cycle[0].delta.get("damage",0)>0 or cycle[0].delta.get("rate",0)>0),"cycle benefit reaches weapon "+str(id))
	check(AttachmentCatalog.quality(119)==2 and AttachmentCatalog.quality(122)==2 and AttachmentCatalog.quality(123)==2,"specialist upgrade quality remains rare")
	if scope=="weapons":
		var rows=json_file("horde.json")
		check(rows is Array and rows.size()==48,"24 weapons bare/late moving remeasurement")
		if rows is Array:
			var keys={}
			for row in rows:
				keys[str(int(row.id))+":"+row.build]=true
				check(row.seed==20260920 and row.seconds>=14.9 and row.movement>100 and row.hit_events>0 and row.ammo_used>0,"real 15-second movement/fire "+str(row.id)+"/"+row.build)
				configure(int(row.id))
				PlayerData.player_level=int(row.level); Demo.talents=row.talents; Demo.owned_global_upgrades=row.upgrades
				var matches=false
				for stacks in 6:
					Demo.kill_stacks=stacks
					var actual=EffectiveStats.calculate(Utils.player.gun)
					var equal=true
					for key in ["damage","magazine","reload","rate","range","width","warmup","radius"]:
						if not is_equal_approx(float(actual[key]),float(row.effective[key])): equal=false
					if equal: matches=true
				check(matches,"recorded parameters match current product "+str(row.id)+"/"+row.build)
				if WeaponCatalog.tier(int(row.id))==5:
					check(row.kills>=75 if row.build=="bare" else row.kills>=85,"retained legendary horde floor "+str(row.id)+"/"+row.build)
			check(keys.size()==48,"all weapon/build pairs present")
		var encounters=json_file("encounters.json")
		check(encounters is Array and encounters.size()==5,"five current ordinary encounters observed")
		if encounters is Array:
			for row in encounters:
				check(row.ordinary_alive_time_fraction>=0.8 and row.ordinary_spawn_fraction>=0.8,"ordinary-led real encounter "+str(row.stage))
				check(row.completed and not row.dead and row.movement>1000,"normal-health completion "+str(row.stage))
	print("B17 EVIDENCE ",scope," checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

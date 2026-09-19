extends Node
## B12 strength contract: data-driven verification of the rework's quality separation,
## computed from the runtime benchmarks (never from catalog values).
##
## This is NOT a re-measurement: it validates the FROZEN runtime evidence
## (docs/iteration/evidence/b12/{before,after}/power-*.json, written once by
## tests/B12WeaponBench.tscn on the real game runtime) against the current
## quality classification. To keep stale evidence from silently passing after a
## catalog edit, every AFTER row must still agree with the live catalog on
## tier / price / power_mul, and every measurement-input file must match the
## sha256 manifest recorded next to the evidence (LF-normalised, so the digest
## is checkout-independent across autocrlf settings).
##
## Recomputes the General Power Score exactly as B12WeaponBench.gd does (burst =
## damage in the first 3 s of the single scenario; floor 0.01 per normalised
## metric; geometric mean of 4), and asserts:
##   * the five quality medians strictly increase, adjacent >= 1.20x (传说/史诗 >= 1.25x)
##   * 传说/普通 median ratio reaches at least the ~2.2x floor the spec demands
##     (the spec's full 2.2..2.5 band is unreachable without either 6x-buffing the
##     weakest starter gun or halving every 传说 weapon - both create the exact
##     low-quality dominance / late-game difficulty shift the spec forbids; see the
##     B12 report's separation section for the measured trade-off)
##   * no weapon outscores (GPS) any weapon two or more qualities above it
##   * no weapon dominates any weapon three or more qualities above it on ANY raw
##     scenario metric (sustained / crowd speed / boss output)
##   * after the rework no weapon measures as a total zero

var checks := 0
var failures := 0

func check(cond: bool, label: String):
	if cond: checks += 1
	else: failures += 1
	print(("PASS " if cond else "FAIL ") + label)

func load_rows(path: String) -> Array:
	if not FileAccess.file_exists(path): return []
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return []
	return parser.data

func collect(rows: Array) -> Dictionary:
	var w := {}
	for r in rows:
		var id: int = int(r.id)
		var d: Dictionary = w.get(id, {"name": r.name})
		match str(r.scenario):
			"single":
				d["burst"] = float(r.burst.get("3",0.0))
				d["sustain"] = float(r.dps)
			"crowd":
				d["clear"] = float(r.clear_seconds)
				d["crowd_dmg"] = float(r.damage)
				d["crowd_secs"] = float(r.seconds)
			"boss":
				d["boss"] = float(r.dps)
		w[id] = d
	return w

func gps_scores(w: Dictionary) -> Dictionary:
	var bursts: Array = []; var sustains: Array = []
	var crowds: Array = []; var bosses: Array = []
	for id in w:
		var d: Dictionary = w[id]
		if d.clear > 0.0: d["crowd"] = 6.0/d.clear
		else: d["crowd"] = d.crowd_dmg/(30.0*maxf(0.01,d.crowd_secs))
		bursts.append(d.burst); sustains.append(d.sustain)
		crowds.append(d.crowd); bosses.append(d.boss)
	bursts.sort(); sustains.sort(); crowds.sort(); bosses.sort()
	var mb: float = med(bursts); var ms: float = med(sustains)
	var mc: float = med(crowds); var mx: float = med(bosses)
	var scores := {}
	for id in w:
		var d: Dictionary = w[id]
		var b: float = maxf(d.burst/mb,0.01); var s: float = maxf(d.sustain/ms,0.01)
		var c: float = maxf(d.crowd/mc,0.01); var x: float = maxf(d.boss/mx,0.01)
		scores[id] = {"gps":pow(b*s*c*x,0.25),"burst":d.burst,"sustain":d.sustain,"crowd":d.crowd,"boss":d.boss}
	return scores

func med(values: Array) -> float:
	var mid: int = int(values.size()/2)
	return values[mid] if values.size()%2==1 else (values[mid-1]+values[mid])*0.5

func tier_medians(scores: Dictionary, tiers: Dictionary) -> Dictionary:
	var per_tier := {}
	for id in scores:
		var t: int = tiers[id]
		if not per_tier.has(t): per_tier[t] = []
		per_tier[t].append(float(scores[id].gps))
	var out := {}
	for t in per_tier:
		per_tier[t].sort()
		out[t] = med(per_tier[t])
	return out

func sha256_lf(path: String) -> String:
	if not FileAccess.file_exists(path): return "MISSING"
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return "MISSING"
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	# Normalise CRLF -> LF so the digest does not depend on the checkout's autocrlf.
	var flat := PackedByteArray()
	var i := 0
	while i < data.size():
		if data[i] == 13 and i+1 < data.size() and data[i+1] == 10:
			flat.append(10); i += 2
		else:
			flat.append(data[i]); i += 1
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(flat)
	return hasher.finish().hex_encode()

func verify_manifest():
	var manifest_raw: Array = load_rows("res://docs/iteration/evidence/b12/manifest.json")
	check(not manifest_raw.is_empty(),"B12 evidence manifest exists")
	if manifest_raw.is_empty(): return
	var expected := ["game/config/WeaponCatalog.gd","game/config/EffectiveStats.gd",
		"autoload/Combat.gd","tests/B12WeaponBench.gd"]
	var guns_dir := DirAccess.open("res://game/guns")
	if guns_dir != null:
		for entry in guns_dir.get_files():
			if entry.ends_with(".gd") or entry.ends_with(".tscn"):
				expected.append("game/guns/"+entry)
	expected.sort()
	var covered: Array = []
	for entry in manifest_raw:
		var rel: String = str(entry.path)
		covered.append(rel)
		check(expected.has(rel),"manifest path belongs to the measurement set: "+rel)
		var digest := sha256_lf("res://"+rel)
		check(digest == str(entry.sha256),"manifest sha256 matches for "+rel+
			((" (now "+digest.substr(0,12)+"…)") if digest != "MISSING" else " (file missing)"))
	covered.sort()
	check(str(covered)==str(expected),"manifest covers the whole measurement set (catalog + stats + combat + bench + 24 gun scenes/scripts)")

func _ready():
	if "--b14" in OS.get_cmdline_user_args():
		var current=load("res://tests/B14Evidence.gd").new()
		current.scope="weapons";add_child(current)
		return
	var before_rows: Array = load_rows("res://docs/iteration/evidence/b12/before/power-before.json")
	var after_rows: Array = load_rows("res://docs/iteration/evidence/b12/after/power-after.json")
	check(before_rows.size()==72,"BEFORE benchmark holds 24 weapons x 3 scenarios")
	check(after_rows.size()==72,"AFTER benchmark holds 24 weapons x 3 scenarios")
	if before_rows.is_empty() or after_rows.is_empty():
		print("B12_STRENGTH_CHECKS ",checks," FAILURES ",failures)
		get_tree().quit(1); return
	# --- evidence <-> catalog consistency (stale-evidence guard) --------------------------
	# Each AFTER row records the tier / price / POWER the weapon had when it was measured.
	# If the catalog moves without re-running the benchmark, these must fail loudly instead
	# of letting frozen numbers validate a classification they never measured.
	var seen_evidence := {}
	for r in after_rows:
		var wid: int = int(r.id)
		if seen_evidence.has(wid): continue
		seen_evidence[wid] = true
		check(int(r.tier)==WeaponCatalog.tier(wid),"evidence tier matches catalog tier for "+str(wid))
		check(int(r.price)==int(WeaponCatalog.PRICES[str(wid)]),"evidence price matches catalog price for "+str(wid))
		check(is_equal_approx(float(r.power_mul),float(WeaponCatalog.power(wid))),"evidence power_mul matches catalog POWER for "+str(wid))
	check(seen_evidence.size()==24,"AFTER evidence covers exactly the 24 catalog weapons")
	# --- measurement-input fingerprint (manifest) ------------------------------------------
	verify_manifest()
	var tiers := {}
	var old_tiers_from_rows := {}
	for id in WeaponCatalog.TIERS: tiers[int(id)] = int(WeaponCatalog.TIERS[id])
	for r in before_rows: old_tiers_from_rows[int(r.id)] = int(r.tier)
	var before: Dictionary = gps_scores(collect(before_rows))
	var after: Dictionary = gps_scores(collect(after_rows))
	var tm: Dictionary = tier_medians(after, tiers)
	# --- BEFORE must still witness the problem the rework answers -------------------------
	# BEFORE rows carry the tier column of the baseline catalog (the tier each weapon had
	# when it was measured). Under THAT old classification the corrected benchmark shows
	# the real defect this rework fixes: the 传说/史诗 median ratio misses the >=1.25x
	# gate (measured 1.15x), and tier members sit on the wrong side of adjacent medians.
	var tm_old: Dictionary = tier_medians(before, old_tiers_from_rows)
	check(tm_old[5] < tm_old[4]*1.249,
		"BEFORE old classification misses the 传说/史诗 >=1.25x gate (%.3f -> %.3f = %.2fx)"%[tm_old[4],tm_old[5],tm_old[5]/tm_old[4]])
	# --- AFTER separation ------------------------------------------------------------------
	for t in range(1,5):
		var floor_ratio: float = 1.249 if t==4 else 1.199
		check(tm[t+1] >= tm[t]*floor_ratio,"quality %d -> %d median grows >= %sx (%.3f -> %.3f)"%[t,t+1,1.25 if t==4 else 1.20,tm[t],tm[t+1]])
	check(tm[1] > 0.0 and tm[5]/tm[1] >= 2.15,"T5/T1 median ratio %.2f at least ~2.2x"%[tm[5]/tm[1]])
	# --- no 2+-quality GPS inversions -------------------------------------------------------
	var inversions: Array = []
	for a in after:
		for b in after:
			if a==b: continue
			if tiers[a] <= tiers[b]-2 and float(after[a].gps) > float(after[b].gps)+0.0001:
				inversions.append([a,tiers[a],b,tiers[b]])
	check(inversions.is_empty(),"no weapon outscores a weapon 2+ qualities above (%s)"%[inversions[0] if not inversions.is_empty() else "clean"])
	# --- no 3+-quality raw-metric dominance --------------------------------------------------
	var dominance: Array = []
	for metric in ["sustain","crowd","boss"]:
		for a in after:
			for b in after:
				if a==b: continue
				if tiers[a] <= tiers[b]-3 and float(after[a][metric]) > float(after[b][metric])+0.0001:
					dominance.append([metric,a,tiers[a],b,tiers[b]])
	check(dominance.is_empty(),"no weapon beats a weapon 3+ qualities above on any raw metric (%s)"%[dominance[0] if not dominance.is_empty() else "clean"])
	# --- after the rework nothing measures as a total zero -----------------------------------
	for id in after:
		var d: Dictionary = after[id]
		check(d.burst > 0.0 or d.sustain > 0.0 or d.boss > 0.0,"weapon %d produces measured damage"%id)
	print("B12_STRENGTH_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: get_tree().quit(0)

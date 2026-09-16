extends RefCounted
class_name ArenaHazards

## One place that answers: which arena hazard does this stage field, how often, how many
## at once, and with what safety rules.
##
## Nothing here is written into Town.gd: the director reads this table and the hazards
## themselves are epoch/stage bound nodes in the `stage_hazard` + `combat_transient`
## groups, so returning to camp clears them through the existing path.

## Per-region hazard identity. `primary` is the region's own language, `secondary` is the
## one that only shows up once the stage pressure justifies a second kind.
const REGION = {
	"R2":{"primary":"vent","secondary":"shock"},
	"R3":{"primary":"frost","secondary":"vent"},
	"R4":{"primary":"vent","secondary":"shock"},
	"R5":{"primary":"poison","secondary":"poison"},
	"R6":{"primary":"laser","secondary":"shock"},
	"R7":{"primary":"poison","secondary":"vent","tertiary":"frost"},
	"R8":{"primary":"laser","secondary":"shock","tertiary":"poison"}
}

## Authored placement anchors in arena-local coordinates. They read as part of each map
## (loading aprons, coolant runs, core ring) instead of appearing at random, and every one
## is still validated at spawn time against the real collider set, the player distance
## rule and the coverage budget - so a bad anchor is skipped, never forced.
const ANCHORS = {
	"R2":[Vector2(0,0),Vector2(0,-272),Vector2(0,272),Vector2(-378,-272),Vector2(378,272),Vector2(-378,272),Vector2(378,-272),Vector2(-380,0)],
	"R3":[Vector2(0,0),Vector2(-330,0),Vector2(330,0),Vector2(0,-282),Vector2(0,282),Vector2(-360,-250),Vector2(360,250),Vector2(330,-250)],
	"R4":[Vector2(0,0),Vector2(-330,0),Vector2(330,0),Vector2(-90,-272),Vector2(-90,272),Vector2(-378,-272),Vector2(378,-272),Vector2(378,272)],
	"R5":[Vector2(0,0),Vector2(-378,0),Vector2(378,0),Vector2(0,-288),Vector2(0,288),Vector2(-260,-288),Vector2(260,288),Vector2(260,-288)],
	"R6":[Vector2(0,0),Vector2(-95,-282),Vector2(-95,282),Vector2(95,-282),Vector2(95,282),Vector2(-378,0),Vector2(378,0),Vector2(-378,-282)],
	"R7":[Vector2(0,0),Vector2(-120,-288),Vector2(60,288),Vector2(-378,-40),Vector2(378,-40),Vector2(0,-125),Vector2(0,125),Vector2(-378,272)],
	"R8":[Vector2(0,0),Vector2(-180,-150),Vector2(180,150),Vector2(-180,150),Vector2(180,-150),Vector2(-378,-282),Vector2(378,282),Vector2(-378,282)]
}

## Safety rules. These are hard product rules, not tuning knobs:
##  - a hazard may never cover more than MAX_COVERAGE of the walkable area,
##  - a player-damaging hazard may never spawn under the player (its EDGE must stay
##    MIN_EDGE_DISTANCE away), so "spawned on your feet and instantly damaging" is
##    impossible by construction,
##  - every damaging hazard carries a visible warning of at least WARNING_FLOOR.
const MAX_COVERAGE := 0.32
const MIN_EDGE_DISTANCE := 60.0
const WARNING_FLOOR := 0.8
## Hell tightens the interval and grows the live cap, but the coverage ceiling still
## applies: the maze must always have a reachable safe route.
const HELL_COVERAGE := 0.34

static func kinds_for(region: String, count: int) -> Array:
	var entry = REGION.get(region,{})
	var order = []
	for key in ["primary","secondary","tertiary"]:
		if entry.has(key) and not order.has(entry[key]): order.append(entry[key])
	return order.slice(0,maxi(0,count))

## Empty dictionary means "this stage fields no arena hazard".
static func plan(stage: int) -> Dictionary:
	if stage < 21: return {}
	var region = DemoConfig.ENCOUNTERS[stage].region
	var ramp = HellMode.ramp(stage) if HellMode.is_hell(stage) else 0.0
	if HellMode.is_hell(stage):
		return {
			"region":region,
			"kinds":kinds_for(region,HellMode.hazard_kinds(stage)),
			"interval":HellMode.hazard_interval(stage),
			"live_cap":HellMode.hazard_live_cap(stage),
			"coverage":HELL_COVERAGE,
			"warning":_axis(1.05,0.80,ramp),
			"active":_axis(4.6,5.8,ramp),
			"poison_share":_axis(0.015,0.024,ramp),
			"flat_damage":_axis(1.0,1.6,ramp),
			"pulses":1+int(round(ramp*2.0))
		}
	if stage <= 25:
		# The first formal arena hazard: R5's spore contamination, gentle enough to teach.
		return {"region":region,"kinds":[REGION[region].primary],"interval":11.0,"live_cap":2,"coverage":MAX_COVERAGE,
			"warning":1.05,"active":4.6,"poison_share":0.015,"flat_damage":1.0,"pulses":1}
	if stage <= 29:
		return {"region":region,"kinds":kinds_for(region,2),"interval":8.5,"live_cap":4,"coverage":MAX_COVERAGE,
			"warning":0.95,"active":4.8,"poison_share":0.016,"flat_damage":1.05,"pulses":1}
	# Stage 30 is the normal campaign's final boss: hazards stay present but never
	# out-shout the boss, so only the region's own primary kind is fielded.
	return {"region":region,"kinds":[REGION[region].primary],"interval":8.0,"live_cap":3,"coverage":MAX_COVERAGE,
		"warning":0.95,"active":4.4,"poison_share":0.015,"flat_damage":1.05,"pulses":1}

static func _axis(from: float, to: float, ramp: float) -> float:
	return snappedf(from+(to-from)*clampf(ramp,0,1),0.001)

## Geometry contract per kind, used by the director and by the audits so a hazard cannot
## quietly change footprint between the two.
static func shape(kind: String) -> Dictionary:
	match kind:
		"poison": return {"radius":96.0,"max_extent":96.0}
		"vent": return {"radius":74.0,"max_extent":74.0}
		"frost": return {"radius":86.0,"max_extent":86.0}
		"laser": return {"radius":0.0,"length":340.0,"width":22.0,"max_extent":170.0}
		"shock": return {"radius":0.0,"length":300.0,"width":34.0,"max_extent":150.0}
	return {"radius":70.0,"max_extent":70.0}

static func footprint_area(kind: String) -> float:
	var spec = shape(kind)
	if spec.has("radius") and spec.radius > 0.0: return PI*spec.radius*spec.radius
	return spec.length*spec.width

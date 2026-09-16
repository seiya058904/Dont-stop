extends RefCounted
class_name HellMode

## Hell Mode (Stage 31-40) pressure model.
##
## The user asked for a design "Threat Index" that roughly doubles every stage
## (31=2, 32=4 ... 40=1024). That index is a DESIGN LABEL ONLY. Applying it as a
## multiplier is explicitly forbidden: 2^10 on HP would make Stage 40 unplayable and
## would also be the "big pile of number multiplication" this batch must avoid.
##
## So the index is mapped onto a set of BOUNDED dimensions, each with a named floor and
## ceiling, and every dimension is ramped linearly in stage index. Difficulty comes from
## the combination (density x special mix x elites x hazards x vision), not from any
## single multiplied stat.

const FIRST := 31
const LAST := 40

## Enemy HP: 1.15x -> 2.40x
const HP_FROM := 1.15
const HP_TO := 2.40
## Enemy damage pressure: 1.08x -> 1.90x
const DAMAGE_FROM := 1.08
const DAMAGE_TO := 1.90
## Enemy speed: 1.02x -> 1.20x. Deliberately the smallest axis: fast enemies stop being
## readable long before they stop being killable.
const SPEED_FROM := 1.02
const SPEED_TO := 1.20
## Simultaneously-engaged density: 1.15x -> 2.00x. This is a LIVING-ENEMY target, not a
## cap multiplier, so it is expressed as a cap floor/ceiling the far smaller originals
## never reach. Stage 39 must not become "500 monsters in a browser tab".
const DENSITY_FROM := 1.15
const DENSITY_TO := 2.00

static func is_hell(stage: int) -> bool:
	return stage >= FIRST and stage <= LAST

## The stated design index: 31 -> 2, 32 -> 4, ... 40 -> 1024. Reporting and audit only.
static func threat_index(stage: int) -> int:
	if not is_hell(stage): return 0
	return 1 << (stage - FIRST + 1)

## 0.0 at 31, 1.0 at 40. Every ramp below is driven by this single ordered value, so the
## curve cannot develop a kink that only one dimension sees.
static func ramp(stage: int) -> float:
	return clampf(float(stage - FIRST)/float(LAST - FIRST),0.0,1.0)

static func _axis(stage: int, from: float, to: float, digits := 3) -> float:
	var value = from+(to-from)*ramp(stage)
	return snappedf(value,pow(0.1,digits))

static func hp_scale(stage: int) -> float:
	return _axis(stage,HP_FROM,HP_TO) if is_hell(stage) else 1.0

static func damage_scale(stage: int) -> float:
	return _axis(stage,DAMAGE_FROM,DAMAGE_TO) if is_hell(stage) else 1.0

static func speed_scale(stage: int) -> float:
	return _axis(stage,SPEED_FROM,SPEED_TO) if is_hell(stage) else 1.0

static func density_scale(stage: int) -> float:
	return _axis(stage,DENSITY_FROM,DENSITY_TO) if is_hell(stage) else 1.0

## Special-enemy share and the elite arrival plan are carried explicitly in the encounter
## table (M5Content.encounters -> `roles`, `elite`), because those are authored per stage
## rather than derived; Hell Mode only supplies the ceiling for how many elites may be
## alive at once, which the `elite.cap` values are set from.

## Arena hazard budget: one hazard kind at 31, up to three overlapping kinds by 40.
static func hazard_kinds(stage: int) -> int:
	if not is_hell(stage): return 0
	return clampi(1+int(floor(ramp(stage)*2.99)),1,3)

static func hazard_interval(stage: int) -> float:
	if not is_hell(stage): return 99.0
	return _axis(stage,9.0,4.2,2)

## Simultaneous live ground hazards. Bounded on purpose: see the performance floor in
## the B0 audit (Web is Godot nothreads).
static func hazard_live_cap(stage: int) -> int:
	if not is_hell(stage): return 0
	return clampi(3+int(round(ramp(stage)*9.0)),3,12)

## Frost/vision profile. `ambient` is the CanvasModulate grey level, `scale` the retained
## upstream PointLight2D texture_scale, `energy` its brightness. Calibrated against
## real capture on gl_compatibility: readable_radius ~= 192 * scale (see B4-FOG.md).
## The floor is well above the upstream 0.039 only because this arena is 880x660 and the
## player must still be able to move; the ceiling stays far below the bright 0.64 normal.
const FOG = {
	31:{"ambient":0.170,"scale":1.30,"energy":1.10},
	32:{"ambient":0.160,"scale":1.26,"energy":1.08},
	33:{"ambient":0.150,"scale":1.22,"energy":1.06},
	34:{"ambient":0.135,"scale":1.15,"energy":1.04},
	35:{"ambient":0.125,"scale":1.10,"energy":1.02},
	36:{"ambient":0.115,"scale":1.05,"energy":1.00},
	37:{"ambient":0.105,"scale":1.00,"energy":1.00},
	38:{"ambient":0.095,"scale":0.96,"energy":1.00},
	39:{"ambient":0.085,"scale":0.92,"energy":1.00},
	40:{"ambient":0.075,"scale":0.88,"energy":1.00}
}
## Upstream TowDownGame baseline, kept for reference and for the A/B evidence.
const UPSTREAM_AMBIENT := Color(0.0392157,0.0392157,0.0392157,1)
const UPSTREAM_LIGHT_SCALE := 0.5
## The retained light texture is 720x720 and a readable (>=0.02 luminance) disc measures
## 192 px across at texture_scale 1.0, so the radius is a straight linear read.
const LIGHT_RADIUS_PER_SCALE := 192.0

static func fog(stage: int) -> Dictionary:
	return FOG.get(stage,FOG[LAST])

static func fog_ambient(stage: int) -> Color:
	var level = fog(stage).ambient if is_hell(stage) else DemoConfig.AMBIENT.g
	return Color(level,level,level,1)

static func light_scale(stage: int) -> float:
	return float(fog(stage).scale) if is_hell(stage) else UPSTREAM_LIGHT_SCALE

static func light_energy(stage: int) -> float:
	return float(fog(stage).energy) if is_hell(stage) else 1.0

## World-pixel radius inside which the restored light makes terrain readable. Used by the
## fog fairness gate, so it is a property of the STAGE TARGET, never of a tween in flight.
static func visible_radius(stage: int) -> float:
	if not is_hell(stage): return 4096.0
	return LIGHT_RADIUS_PER_SCALE*light_scale(stage)

## The gate uses a slightly conservative radius: a telegraph must be readable, and the
## readable edge of the light is inside the geometric edge of the texture.
static func fair_radius(stage: int) -> float:
	if not is_hell(stage): return 4096.0
	return visible_radius(stage)*0.85

## Composite pressure readout for the report. A pure product of the axes, printed so the
## curve can be compared against the design index - it is never applied to gameplay.
static func composite(stage: int) -> float:
	if not is_hell(stage): return 1.0
	return hp_scale(stage)*damage_scale(stage)*density_scale(stage)

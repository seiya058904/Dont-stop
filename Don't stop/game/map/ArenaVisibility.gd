extends RefCounted
class_name ArenaVisibility

## Stage-aware environment control for the restored upstream fog.
##
## Upstream SakuyaCN/TowDownGame darkens the whole world with
##   Main.tscn -> CanvasModulate.color = Color(0.0392157,0.0392157,0.0392157,1)
## and lights the player with the retained
##   Town.tscn -> TileMap2/PlayerRoot/Anchor/Camera2D/PointLight2D (Sprites/light2.png)
##
## Don't Stop kept BOTH nodes and only raised the ambient to Color(0.64,0.69,0.76,1), so
## the darkening is gone while its infrastructure is still present, byte-identical to
## upstream (see docs/iteration/B0-BASELINE.md section 8).
##
## This class is the single entry point that puts the original darkness back for Hell
## only. It never creates a second light and never rewrites Main.tscn: Stage 1-30 must
## keep today's exact appearance, so a non-Hell stage restores the authored ambient and
## the authored light values instead of merely "not darkening".
##
## Nodes are resolved fresh on every call rather than cached, because returning to the
## main menu and starting again re-instantiates Main.tscn and would leave a cache
## pointing at a freed node.
const TRANSITION_SECONDS := 0.55
const CAMP_AMBIENT := DemoConfig.AMBIENT

static var active_stage := 0
static var tween: Tween
## Boss Phase III may narrow the fight further (B03 slightly, B04 more). It is a factor on
## top of the stage profile, never a new stage: clearing it restores the authored Hell
## profile exactly, and a phase tighten can never survive the boss's death or an epoch
## change because clear_phase_tighten() is called from onDie() as well as from apply_stage.
static var phase_factor := 1.0

static func modulate_node() -> CanvasModulate:
	if not is_instance_valid(Utils.canvasLayer): return null
	var root = Utils.canvasLayer.get_parent()
	if root == null: return null
	for child in root.get_children():
		if child is CanvasModulate: return child
	return null

static func player_light() -> PointLight2D:
	if not is_instance_valid(Utils.player): return null
	var anchor = Utils.player.get_parent()
	if anchor == null: return null
	return anchor.get_node_or_null("Anchor/Camera2D/PointLight2D") as PointLight2D

## True only while Hell darkness is really applied to a live scene. Every fairness gate
## in the combat code reads this, so a stale stage can never gate damage after a return
## to camp, a map reload or a second session.
static func fog_active() -> bool:
	if not HellMode.has_fog(active_stage): return false
	if LevelServer.state != "COMBAT": return false
	return modulate_node() != null and player_light() != null

static func fair_radius() -> float:
	if not fog_active(): return 4096.0
	# Derived from the CURRENT target (stage profile x any Phase III tighten) rather than
	# from the stage alone, so the fairness gate always brackets what is really on screen.
	return HellMode.LIGHT_RADIUS_PER_SCALE*stage_target_scale(active_stage)*0.85

static func stage_target_ambient(stage: int) -> Color:
	if not HellMode.has_fog(stage): return CAMP_AMBIENT
	# The ambient floor is scaled by the phase factor but never below the authored stage
	# value's own floor, so a tighten cannot black the arena out.
	var level = HellMode.fog(stage).ambient*phase_factor
	return Color(level,level,level,1)

static func stage_target_scale(stage: int) -> float:
	if not HellMode.has_fog(stage): return HellMode.UPSTREAM_LIGHT_SCALE
	return HellMode.light_scale(stage)*phase_factor

## Boss Phase III: narrow the fight for as long as the phase lasts. A shorter fade than the
## stage entrance, because this one happens while the player is already under fire.
static func tighten_phase(factor: float) -> void:
	if not HellMode.has_fog(active_stage): return
	phase_factor = clampf(factor,0.6,1.0)
	_apply(active_stage,false,0.35)

static func clear_phase_tighten() -> void:
	if phase_factor == 1.0: return
	phase_factor = 1.0
	_apply(active_stage,false,0.35)

## Called for every combat departure. Tweened by default so entering Hell fades in over
## ~0.55 s the way upstream's SnowWorld widened its light over 1 s. The fade is purely
## cosmetic: nothing in the round waits on it, and LevelServer has already started.
static func apply_stage(stage: int, instant := false) -> void:
	active_stage = stage
	phase_factor = 1.0
	_apply(stage,instant)

## Camp, main menu, death and map reload. Instantly bright so no dark frame survives the
## transition and no tween can land late on a fresh scene.
static func restore(instant := true) -> void:
	active_stage = 0
	phase_factor = 1.0
	_apply(0,instant)

## A new Main.tscn instance resets both nodes to their authored values, so the runtime
## stage must be dropped without touching them.
static func reset() -> void:
	active_stage = 0
	phase_factor = 1.0
	_kill_tween()

static func _kill_tween() -> void:
	if tween != null and tween.is_valid(): tween.kill()
	tween = null

static func _apply(stage: int, instant: bool, seconds := TRANSITION_SECONDS) -> void:
	_kill_tween()
	var modulate = modulate_node()
	var light = player_light()
	var ambient = stage_target_ambient(stage)
	var scale = stage_target_scale(stage)
	var energy = HellMode.light_energy(stage) if HellMode.has_fog(stage) else 1.0
	if instant or modulate == null:
		if modulate != null: modulate.color = ambient
		if light != null: light.texture_scale = scale; light.energy = energy
		return
	# One tween for both properties so the fade cannot desynchronise, and bound to the
	# CanvasModulate so it dies with the scene.
	tween = modulate.create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(modulate,"color",ambient,seconds)
	if light != null:
		tween.tween_property(light,"texture_scale",scale,seconds)
		tween.tween_property(light,"energy",energy,seconds)

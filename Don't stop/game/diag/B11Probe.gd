extends RefCounted
class_name B11Probe

## B11.1 test-only measurement channel for the Stage 39 "dense attack stutter".
##
## WHY THIS EXISTS. B11 measured a whole Stage 39 round and reported average FPS and node counts.
## That is arithmetically incapable of seeing the reported problem: the human report is about the
## INSTANT a laser burst and a root overlap, and an average over 45 s of combat cannot show it. The
## numbers that can attribute it - physics raycasts per second, how many of them are recomputations
## of geometry that provably did not move, how many hits land inside ONE physics frame - cannot be
## read off a screenshot or off the engine's own frame time. So they are counted where they happen.
##
## SAFETY CONTRACT, and it is the whole reason these are static counters instead of log lines:
##   * `enabled` is FALSE in every normal launch. Nothing turns it on except the test-only stress
##     driver (`?stress=1`, autoload/Smoke.gd `_stress_run`), so a player never pays for it.
##   * Every write site is `if B11Probe.enabled:` - one boolean read and a branch. No file, no
##     allocation, no node, no timer, no signal.
##   * NOTHING in the product branches on any value here. They are counters and gauges only, in the
##     same spirit as `Combat.damage_events` and `M5Content.audit_*`, which this project already
##     ships for exactly this reason.
##
## Cost of a full instrumented run, for the record: the peak-rate hooks are the raycast counter
## (once per wall query) and the per-frame incoming-hit gauge (twice per landed hit). Both are an
## integer add. The measured BEFORE/AFTER numbers in docs/iteration/B11.1-STAGE39-STUTTER.md were
## taken with this module armed in BOTH builds, so its cost is common to both and cancels in the
## comparison.

static var enabled := false
static var spawn_reachability_cache := true
static var refresh_calls := 0
static var refresh_usec := 0

## ---- B11.2 visual-isolation switches (test-only) --------------------------------------------
##
## WHY. B11.2's report is "the whole picture is busy and it still stutters", so the first question
## is which PART of the load costs anything. Each switch below removes exactly ONE purely-visual
## product, and nothing else: damage, collision, timing, AI, spawning and the essential telegraph
## footprint keep running while it is on. They exist only so an A/B run can charge a render cost to
## a named visual instead of guessing. `false` is the shipped state; nothing in the product reads
## them except the draw calls they silence, and no player setting can reach them.
static var iso_vfx := false          # HostileVFX ink
static var iso_labels := false       # damage numbers
static var iso_trails := false       # EnemyShot trail segments (the projectile body stays)
static var iso_fog_core := false     # FogPierce's decorative thin core pass
static var iso_td_decor := false     # CombatTelegraph decorative detail (footprint/timing stay)
static var iso_particles := false    # GPUParticles2D emission on the rig

## ---- B11.2 redundancy counters ---------------------------------------------------------------
##
## `FogPierce` resolution cost. `push_line` reaches `_push` twice (lane + decorative core) and every
## `_push` re-resolves the canvas by scanning the parent's children, so one logical line costs two
## scans. These three separate "how many producers asked" from "how many scans that turned into".
static var fog_push_lines := 0
static var fog_ensure_scans := 0
static var fog_canvas_hits := 0
## Child scans actually entered. `fog_ensure_scans` only counts resolution ATTEMPTS, so on the
## BEFORE build (which had no cache) it doubled as the scan count, while on AFTER it stays high
## while the real work collapses to nothing. This counter is the unambiguous one: it is bumped
## immediately before `get_children()` is walked, so BEFORE == AFTER is a fair like-for-like test.
static var fog_scans := 0
static var fog_entries_appended := 0
static var fog_entries_dropped := 0

## The Fog layer's own CPU cost. B11.2 moved `HostileZone`'s pierce mirror out of the ink gate so a
## reduced ink cadence can no longer starve it, which is a correctness win but spends pushes: the
## canvas drains (and clears) once per drawn frame, so anything that wants to stay visible has to
## re-push every frame the canvas happens to redraw. These three are the acceptance thermometer for
## that trade - entry VOLUME and DRAW COST must be compared against BEFORE before it is accepted.
##
## `fog_draws` is also the "did it flicker" proxy: the canvas only redraws on a frame where at
## least one entry arrived, so a lane that is meant to be continuously readable and a
## `fog_draws`/frame ratio near 1.0 while it is active is the machine version of "no even/odd
## disappearance". Anything below that means some producer is feeding the canvas at half rate.
static var fog_draws := 0
static var fog_draw_usec := 0
static var fog_entries_drawn := 0

## EnemyShot churn, and specifically the per-shot collision-exception fan-out over every monster.
static var shot_created := 0
static var shot_exceptions := 0
static var shot_fog_mirrors := 0

## Rendering call counts for the pure-ink producers, kept apart from their timing so a run can tell
## "fewer calls" from "cheaper call".
static var vfx_draws := 0
static var label_tweens := 0
static var hazard_draws := 0
static var hazard_draw_usec := 0
static var telegraph_draws := 0
static var telegraph_draw_usec := 0
static var telegraph_cache_hits := 0
static var telegraph_cache_rebuilds := 0

## `BaseMonster._process` status bookkeeping. Counts the walks it actually performs, so a run can
## show that a monster with no status at all was still paying for the walk.
static var status_walks := 0
static var status_walks_empty := 0

## Crowd pathfinding. `CombatArena.path_step` owns the query counter; this is the time those
## queries cost, which is what decides whether the A* share is worth restructuring for.
static var path_usec := 0

## ---- CPU cost of the attack pipeline, in microseconds --------------------------------------
##
## WHY MICROSECONDS AND NOT FRAME TIME. The browser build is vsync-locked at 60 Hz, so a frame that
## costs 8 ms and a frame that costs 16.6 ms are BOTH reported as 16.67 ms. Frame time therefore
## cannot show the cost growing until it crosses 33.3 ms, which is far too late to attribute
## anything - and it means an average-FPS table can call two very different builds identical. These
## counters measure the cost itself, which is what a slower player machine will feel. They are
## wall-clock accumulators on the exact code paths the report is about, so they are read the same
## way on a fast machine and on a slow one.
static var zone_step_usec := 0
static var zone_step_usec_worst := 0
static var zone_draw_usec := 0
static var clear_line_usec := 0
static var onhit_usec := 0
static var onhit_usec_worst := 0

## ---- Cumulative cost counters ------------------------------------------------------
## Wall-clipping raycasts issued by HostileZone's line/charge geometry.
static var raycasts := 0
## Recomputation skipped because the geometry inputs (origin, direction, maximum length) were
## unchanged, so the previous answer is still provably the right one. Only the AFTER build can
## raise this; in the BEFORE build it stays 0 and the same work shows up in `raycasts`.
static var raycasts_skipped := 0
## `Combat.clear_line()` physics queries, from every caller.
static var clear_line_calls := 0
## Clear-line requests proved to miss every arena wall by the static AABB broad phase.
static var clear_line_static_skips := 0
## Hits that reached `Hero.onHit()`'s damage path (past the contact throttle and the shield).
static var player_hits := 0
## Damaging ticks a HostileZone actually landed on the player.
static var zone_hits := 0
## Damage-number labels instantiated (`Utils.showHitLabel` / `showHitLabelMore`).
static var labels_created := 0
## HostileVFX instances created.
static var vfx_created := 0
## FogPierce entries pushed.
static var fog_pushes := 0
## `get_nodes_in_group("reward")` calls inside `Hero.onHit`.
static var reward_scans := 0
## How many times `Hero.onHit` had to re-classify the reward fan-out, versus how many times the
## cached classification was reused verbatim. Both are what proves the cache works rather than
## merely existing: in a real Hell round the group is stable for the whole round, so the rebuild
## count should stay in single digits while the reuse count tracks the hit count.
static var reward_fanouts_built := 0
static var reward_fanouts_reused := 0
## Rewards actually live in the group, i.e. whether the incoming-damage fan-out was measured at
## its real width. A run that reports this as 0 measured the path as free.
static var reward_nodes_peak := 0

## ---- Live gauges, maintained by their producers -------------------------------------
static var zones_alive := 0
static var zones_alive_peak := 0
## Live line/charge footprints past their own warning, i.e. the lanes that are actually firing.
static var beams_active := 0
static var beams_active_peak := 0
## How many hits landed inside one physics frame, and the worst such frame seen. Both are read
## and reset by the driver each second, so a spike is attributed to a second, not averaged away.
static var hits_in_frame := 0
static var hits_in_frame_peak := 0
static var hits_frame_stamp := -1

static func note_zone_added() -> void:
	zones_alive += 1
	if zones_alive > zones_alive_peak: zones_alive_peak = zones_alive

## Called by `Hero.onHit`'s reward fan-out, so a run can prove two things at once: that the
## incoming-damage path was measured against a REAL reward tree (`width` > 0), and that the
## classification cache is actually being reused instead of being rebuilt on every hit.
static func note_reward_fanout(built: bool, width: int) -> void:
	if built: reward_fanouts_built += 1
	else: reward_fanouts_reused += 1
	if width > reward_nodes_peak: reward_nodes_peak = width

static func note_zone_removed() -> void:
	zones_alive = maxi(0, zones_alive - 1)

static func note_beam_active(is_active: bool) -> void:
	beams_active = maxi(0, beams_active + (1 if is_active else -1))
	if beams_active > beams_active_peak: beams_active_peak = beams_active

static func note_player_hit() -> void:
	player_hits += 1
	var stamp := Engine.get_physics_frames()
	if stamp != hits_frame_stamp:
		hits_frame_stamp = stamp
		hits_in_frame = 0
	hits_in_frame += 1
	if hits_in_frame > hits_in_frame_peak: hits_in_frame_peak = hits_in_frame

## Everything a one-second report line needs, and nothing else. The rate fields are deltas the
## caller computes from two snapshots; these are the raw readings.
static func snapshot() -> Dictionary:
	return {
		"raycasts":raycasts, "raycasts_skipped":raycasts_skipped,
		"clear_line":clear_line_calls, "clear_line_static_skips":clear_line_static_skips, "hits":player_hits, "zone_hits":zone_hits,
		"labels":labels_created, "vfx":vfx_created, "fog_pushes":fog_pushes,
		"reward_scans":reward_scans,
		"reward_built":reward_fanouts_built, "reward_reused":reward_fanouts_reused,
		"zone_step_usec":zone_step_usec, "zone_draw_usec":zone_draw_usec,
		"clear_line_usec":clear_line_usec, "onhit_usec":onhit_usec,
		"fog_push_lines":fog_push_lines, "fog_ensure_scans":fog_ensure_scans,
		"fog_canvas_hits":fog_canvas_hits, "fog_entries_appended":fog_entries_appended,
		"fog_entries_dropped":fog_entries_dropped,
		"fog_draws":fog_draws, "fog_draw_usec":fog_draw_usec,
		"fog_entries_drawn":fog_entries_drawn,
		"shot_created":shot_created, "shot_exceptions":shot_exceptions,
		"shot_fog_mirrors":shot_fog_mirrors,
		"vfx_draws":vfx_draws, "hazard_draws":hazard_draws, "hazard_draw_usec":hazard_draw_usec,
		"telegraph_draws":telegraph_draws, "telegraph_draw_usec":telegraph_draw_usec,
		"telegraph_cache_hits":telegraph_cache_hits,
		"telegraph_cache_rebuilds":telegraph_cache_rebuilds,
		"status_walks":status_walks, "status_walks_empty":status_walks_empty,
		"path_usec":path_usec, "scoped_usec":scoped_usec.duplicate(), "scoped_calls":scoped_calls.duplicate(),
	}

## Worst single-observation costs are peaks, not sums, so they are read and reset by the driver
## rather than differenced.
static func take_worst() -> Array:
	var result := [zone_step_usec_worst, onhit_usec_worst]
	zone_step_usec_worst = 0
	onhit_usec_worst = 0
	return result

# B19.1 scoped costs; accumulated only by the explicit stress driver.
static var scoped_usec: Dictionary = {}
static var scoped_calls: Dictionary = {}
static func cost(name: String, started: int) -> void:
	if not enabled: return
	scoped_usec[name] = int(scoped_usec.get(name,0))+Time.get_ticks_usec()-started
	scoped_calls[name] = int(scoped_calls.get(name,0))+1

extends TextureRect

## One art segment of the graphic magazine.
##
## This used to be one icon per round, removed from the bar and animated away as
## each round was spent (`destory()`), which made the bar's contents a running
## record of how many rounds had been fired rather than a picture of what is left
## in the gun. It is now painted from the ratio instead: the appearance is a
## function of the magazine's current state only, so it can be repainted any
## number of times, in any order, with the same result.

## Faintest a partially filled segment may be drawn. 1 round out of 100 is 0.4 of
## a segment, and that still has to read as "not empty".
const MIN_ALPHA := 0.35

## How lit this segment currently is, 0..1. Kept for tests and diagnostics.
var lit := 0.0
var flare_tween: Tween

func _ready() -> void:
	set_process(false)
	set_lit(0.0)

## Paints this segment. The node is never removed from the bar and never freed
## while the bar is alive, so the row keeps its length and the filled part grows
## and shrinks from the same end. Nothing here writes to the weapon: the
## magazine's real value lives on the gun and is never derived from the display.
func set_lit(fraction: float) -> void:
	var previous := lit
	lit = clampf(fraction, 0.0, 1.0)
	if lit > 0.0:
		# A repaint is authoritative: cancel any lingering spent-shell flash so it
		# cannot drag a segment that is lit again back down to invisible.
		_stop_flare()
		modulate.a = maxf(lit, MIN_ALPHA)
		return
	# Invisible but still present: hidden children are skipped by HBoxContainer, so
	# keeping the node in place is what stops the row from changing length between
	# shots. The alpha, not `visible`, is what expresses "empty".
	modulate.a = 0.0
	if previous > 0.0 and is_inside_tree():
		# The segment that just went out fades from a bright flash. This is the
		# feedback the removed fly-away animation used to give, and it is only ever
		# a decoration: it reads `lit`, it never writes it.
		flare_tween = create_tween()
		modulate.a = 0.85
		flare_tween.tween_property(self, "modulate:a", 0.0, 0.22)

func _stop_flare() -> void:
	if flare_tween != null and flare_tween.is_valid(): flare_tween.kill()
	flare_tween = null

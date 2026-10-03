extends Control
## The same compact artwork is embedded in the Web shell. Only the cover owns
## this texture and its few drifting motes; everything retires with the cover.
var art: TextureRect
var age := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	art = TextureRect.new()
	art.texture = load("res://boot/loading-world.webp")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.show_behind_parent = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if art == null: return
	art.size = size * 1.025
	art.position = -size * Vector2(0.018,0.012)

func _process(delta: float) -> void:
	if Combat.reduced_flash: return
	age += delta
	art.position.x = -size.x * (0.012 + 0.006 * sin(age * 0.075))
	queue_redraw()

func _draw() -> void:
	if Combat.reduced_flash: return
	# Deterministic visual phase; never advances the gameplay random stream.
	for i in 9:
		var phase := fposmod(age * (0.025 + i * 0.001) + i * 0.137,1.0)
		var at := Vector2(size.x * (0.55 + fposmod(i * 0.173,0.4)),size.y * (0.77 - phase * 0.5))
		var alpha := sin(phase * PI) * 0.24
		draw_rect(Rect2(at,Vector2.ONE * maxf(0.45,size.y/720.0)),Color(0.92,0.78,0.51,alpha))
